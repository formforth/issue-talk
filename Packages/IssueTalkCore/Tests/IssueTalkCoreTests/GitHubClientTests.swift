import Foundation
import Testing

@testable import IssueTalkCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private let fixtureIssue = """
  {"id":42,"number":1,"title":"Fixture","body":"Public test data",\
  "html_url":"https://github.com/example/sample/issues/1","updated_at":"2026-01-01T00:00:00Z"}
  """

private func fixtureComment(_ id: Int) -> String {
  """
  {"id":\(id),"body":"Comment \(id)",\
  "html_url":"https://github.com/example/sample/issues/1#issuecomment-\(id)",\
  "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
  """
}

private actor StubTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var responses: [HTTPResponse]

  init(_ responses: [HTTPResponse]) { self.responses = responses }

  func send(_ request: URLRequest) throws -> HTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else { throw URLError(.networkConnectionLost) }
    return responses.removeFirst()
  }
}

private actor TokenGate {
  private var requested = false
  private var tokenContinuation: CheckedContinuation<String, Never>?
  private var readyContinuation: CheckedContinuation<Void, Never>?
  func token() async -> String {
    if requested { return "fixture-oauth-token" }
    requested = true
    readyContinuation?.resume()
    readyContinuation = nil
    return await withCheckedContinuation { tokenContinuation = $0 }
  }
  func waitUntilRequested() async {
    if requested { return }
    await withCheckedContinuation { readyContinuation = $0 }
  }
  func release() {
    tokenContinuation?.resume(returning: "fixture-oauth-token")
    tokenContinuation = nil
  }
}

struct GitHubClientTests {
  private func identity() throws -> IssueIdentity {
    try IssueIdentity(url: #require(URL(string: "https://github.com/example/sample/issues/1")))
  }

  @Test func canonicalIdentityRejectsOtherHostsAndPullRequests() throws {
    let url = try #require(
      URL(string: "https://github.com/Example/Sample/issues/01#issuecomment-2"))
    #expect(try IssueIdentity(url: url) == identity())
    for value in [
      "http://github.com/example/sample/issues/1", "https://github.com.evil.test/a/b/issues/1",
      "https://github.com/a/b/pull/1", "https://github.com/a/b/issues/0",
      "https://user@github.com/a/b/issues/1", "https://github.com/a/b/issues/1/extra",
    ] {
      #expect(throws: IssueTalkError.invalidIssueURL) {
        try IssueIdentity(url: #require(URL(string: value)))
      }
    }
    let encoded = try JSONEncoder().encode(identity())
    #expect(try JSONDecoder().decode(IssueIdentity.self, from: encoded) == identity())
  }

  @Test func paginationKeepsIDsURLsAndAuthorization() async throws {
    let transport = StubTransport([
      HTTPResponse(
        status: 200,
        headers: [
          "Link":
            "<https://api.github.com/repos/example/sample/issues/1/comments?page=2>; rel=\"next\""
        ], data: Data("[\(fixtureComment(2))]".utf8)),
      HTTPResponse(status: 200, data: Data("[\(fixtureComment(3)),\(fixtureComment(2))]".utf8)),
    ])
    let client = GitHubClient(transport: transport, token: { "fixture-oauth-token" })
    let comments = try await client.comments(identity())
    #expect(comments.map(\.id) == [2, 3])
    #expect(comments[0].htmlURL.fragment == "issuecomment-2")
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-oauth-token"
      })
  }

  @Test func paginationNeverSendsCredentialsToAnExternalLink() async throws {
    let transport = StubTransport([
      HTTPResponse(
        status: 200,
        headers: ["link": "<https://evil.test/comments>; rel=\"next\""], data: Data("[]".utf8))
    ])
    let client = GitHubClient(transport: transport, token: { "fixture-oauth-token" })
    await #expect(throws: IssueTalkError.invalidResponse) { try await client.comments(identity()) }
    #expect(await transport.requests.count == 1)
  }

  @Test func getRetriesServerFailuresButNotAuthenticationFailures() async throws {
    let transport = StubTransport([
      HTTPResponse(status: 503), HTTPResponse(status: 200, data: Data(fixtureIssue.utf8)),
    ])
    let client = GitHubClient(
      transport: transport, token: { "fixture-oauth-token" }, sleep: { _ in })
    #expect(try await client.issue(identity()).id == 42)
    #expect(await transport.requests.count == 2)
    let denied = StubTransport([HTTPResponse(status: 401)])
    let deniedClient = GitHubClient(transport: denied, token: { "fixture-oauth-token" })
    await #expect(throws: IssueTalkError.authenticationRequired) {
      try await deniedClient.issue(identity())
    }
    #expect(await denied.requests.count == 1)
  }

  @Test func longRateLimitDoesNotSleepOrRetry() async throws {
    let transport = StubTransport([HTTPResponse(status: 403, headers: ["Retry-After": "120"])])
    let client = GitHubClient(transport: transport, token: { "fixture-oauth-token" })
    await #expect(throws: IssueTalkError.rateLimited) { try await client.issue(identity()) }
    #expect(await transport.requests.count == 1)
  }

  @Test func successfulOperationIsNotPostedAgain() async throws {
    let transport = StubTransport([HTTPResponse(status: 201, data: Data(fixtureComment(7).utf8))])
    let client = GitHubClient(transport: transport, token: { "fixture-oauth-token" })
    let operation = UUID()
    let first = try await client.post("Hello", to: identity(), operationID: operation)
    #expect(try await client.post("Hello", to: identity(), operationID: operation) == first)
    #expect(await transport.requests.count == 1)
    await #expect(throws: IssueTalkError.duplicateOperation) {
      try await client.post("Different", to: identity(), operationID: operation)
    }
  }

  @Test func concurrentSendDuringTokenLookupCannotPostTwice() async throws {
    let transport = StubTransport([HTTPResponse(status: 201, data: Data(fixtureComment(7).utf8))])
    let gate = TokenGate()
    let client = GitHubClient(transport: transport, token: { await gate.token() })
    let operation = UUID()
    let issue = try identity()
    let first = Task { try await client.post("Hello", to: issue, operationID: operation) }
    await gate.waitUntilRequested()
    await #expect(throws: IssueTalkError.uncertainWrite) {
      try await client.post("Hello", to: issue, operationID: operation)
    }
    await gate.release()
    _ = try await first.value
    #expect(await transport.requests.count == 1)
  }

  @Test func uncertainWritesAreNeverRetriedAutomatically() async throws {
    let transport = StubTransport([HTTPResponse(status: 503)])
    let client = GitHubClient(transport: transport, token: { "fixture-oauth-token" })
    let operation = UUID()
    await #expect(throws: IssueTalkError.uncertainWrite) {
      try await client.post("Hello", to: identity(), operationID: operation)
    }
    await #expect(throws: IssueTalkError.uncertainWrite) {
      try await client.post("Hello", to: identity(), operationID: operation)
    }
    #expect(await transport.requests.count == 1)
  }
}
