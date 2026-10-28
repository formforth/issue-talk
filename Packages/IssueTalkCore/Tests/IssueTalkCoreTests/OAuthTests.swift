import Foundation
import Testing

@testable import IssueTalkCore

struct OAuthTests {
  private func configuration() throws -> OAuthConfiguration {
    try OAuthConfiguration(
      clientID: "fixture-client", redirectURI: #require(URL(string: "issuetalk://oauth/callback")),
      broker: #require(URL(string: "https://oauth.example.com")))
  }

  @Test func authorizationRequestsPKCEAndExactRedirect() throws {
    let url = try configuration().authorizationURL(
      state: "fixture-state", challenge: "fixture-challenge")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.contains(URLQueryItem(name: "code_challenge_method", value: "S256")))
    #expect(items.contains(URLQueryItem(name: "redirect_uri", value: "issuetalk://oauth/callback")))
    #expect(items.contains(URLQueryItem(name: "state", value: "fixture-state")))
  }

  @Test func callbackRejectsWrongStateOriginDuplicateParametersAndErrors() throws {
    let config = try configuration()
    #expect(
      try config.code(
        from: #require(URL(string: "issuetalk://oauth/callback?code=fixture&state=expected")),
        expectedState: "expected") == "fixture")
    for value in [
      "issuetalk://oauth/callback?code=fixture&state=wrong",
      "issuetalk://evil/callback?code=fixture&state=expected",
      "issuetalk://oauth/callback?code=one&code=two&state=expected",
      "issuetalk://oauth/callback?code=fixture&state=expected&state=expected",
      "issuetalk://oauth/callback?code=fixture&state=expected&error=denied",
      "https://oauth/callback?code=fixture&state=expected",
    ] {
      #expect(throws: OAuthError.invalidCallback) {
        try config.code(from: #require(URL(string: value)), expectedState: "expected")
      }
    }
  }

  @Test func tokenBrokerMustUseHTTPS() throws {
    #expect(throws: OAuthError.invalidConfiguration) {
      try OAuthConfiguration(
        clientID: "fixture", redirectURI: #require(URL(string: "issuetalk://oauth/callback")),
        broker: #require(URL(string: "http://oauth.example.com")))
    }
  }

  @Test func replyRequiresAnObservedSourceAndPersistsUnresolvedWrites() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let issue = try decoder.decode(
      GitHubIssue.self,
      from: Data(
        """
        {"id":42,"number":1,"title":"Fixture","body":null,
        "html_url":"https://github.com/example/sample/issues/1","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8))
    let comment = try decoder.decode(
      GitHubComment.self,
      from: Data(
        """
        {"id":7,"body":"Raw **Markdown**","html_url":"https://github.com/example/sample/issues/1#issuecomment-7",
        "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8))
    var item = try MonitoredIssue(
      identity: IssueIdentity(url: issue.htmlURL), metadata: issue, comments: [comment])
    item.draft = "My reply"
    #expect(try item.commentBody() == "My reply")
    item.replySource = comment.htmlURL
    #expect(try item.commentBody() == "In reply to \(comment.htmlURL.absoluteString)\n\nMy reply")
    item.writeUnresolved = true
    item.operationID = UUID()
    var workspace = Workspace()
    workspace.issues = [item]
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    #expect(restored.issues[0].writeUnresolved)
    #expect(restored.issues[0].operationID == item.operationID)
    #expect(restored.issues[0].comments[0].body == "Raw **Markdown**")
    item.replySource = URL(string: "https://github.com/example/sample/issues/1#issuecomment-999")
    #expect(throws: IssueTalkError.invalidResponse) { try item.commentBody() }
    item.replySource = nil
    item.draft = "    code\n"
    #expect(try item.commentBody() == "    code\n")
    item.draft = String(repeating: "a", count: 65_537)
    #expect(throws: IssueTalkError.invalidComment) { try item.commentBody() }
    item.draft = " "
    #expect(throws: IssueTalkError.invalidComment) { try item.commentBody() }

  }
}
