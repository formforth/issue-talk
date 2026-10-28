import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// GitHub REST operations have no dependency on inference or voice.
public actor GitHubClient {
  private let transport: any HTTPTransport
  private let token: @Sendable () async throws -> String
  private let sleep: @Sendable (Duration) async throws -> Void
  private var writes: [UUID: Write] = [:]

  private struct Write {
    let issue: IssueIdentity
    let body: String
    var result: GitHubComment?
  }

  public init(
    transport: any HTTPTransport = URLSessionTransport(),
    token: @escaping @Sendable () async throws -> String,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.transport = transport
    self.token = token
    self.sleep = sleep
  }

  public func issue(_ identity: IssueIdentity) async throws -> GitHubIssue {
    let response = try await get(URL(string: "https://api.github.com\(identity.apiPath)")!)
    let issue = try Self.decoder().decode(GitHubIssue.self, from: response.data)
    guard try IssueIdentity(url: issue.htmlURL) == identity, issue.number == identity.number else {
      throw IssueTalkError.invalidResponse
    }
    return issue
  }

  public func comments(_ identity: IssueIdentity) async throws -> [GitHubComment] {
    let path = identity.apiPath + "/comments"
    var next: URL? = URL(string: "https://api.github.com\(path)?per_page=100&page=1")!
    var visited = Set<URL>()
    var comments: [Int64: GitHubComment] = [:]
    while let url = next {
      guard visited.count < 100, visited.insert(url).inserted else {
        throw IssueTalkError.invalidResponse
      }
      let response = try await get(url)
      for comment in try Self.decoder().decode([GitHubComment].self, from: response.data) {
        guard try IssueIdentity(url: comment.htmlURL) == identity,
          comment.htmlURL.fragment == "issuecomment-\(comment.id)"
        else { throw IssueTalkError.invalidResponse }
        comments[comment.id] = comment
      }
      next = try Self.nextPage(response.headers["link"], path: path)
    }
    return comments.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
  }

  /// Reusing an operation returns its result, or blocks an unresolved write; it never posts twice.
  public func post(_ body: String, to identity: IssueIdentity, operationID: UUID) async throws
    -> GitHubComment
  {
    if let previous = writes[operationID] {
      guard previous.issue == identity, previous.body == body else {
        throw IssueTalkError.duplicateOperation
      }
      if let result = previous.result { return result }
      throw IssueTalkError.uncertainWrite
    }
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.utf8.count <= 65_536
    else {
      throw IssueTalkError.invalidResponse
    }
    // Reserve before token lookup as well as HTTP I/O: either can suspend.
    writes[operationID] = Write(issue: identity, body: body)
    var request: URLRequest
    do {
      request = try await self.request(
        URL(string: "https://api.github.com\(identity.apiPath)/comments")!)
    } catch {
      writes.removeValue(forKey: operationID)
      throw error
    }
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["body": body])
    let response: HTTPResponse
    do { response = try await transport.send(request) } catch {
      throw IssueTalkError.uncertainWrite
    }
    if [400, 401, 403, 404, 422, 429].contains(response.status) {
      writes.removeValue(forKey: operationID)
      try Self.check(response)
    }
    guard response.status == 201,
      let comment = try? Self.decoder().decode(GitHubComment.self, from: response.data),
      (try? IssueIdentity(url: comment.htmlURL)) == identity,
      comment.htmlURL.fragment == "issuecomment-\(comment.id)"
    else { throw IssueTalkError.uncertainWrite }
    writes[operationID]?.result = comment
    return comment
  }

  private func request(_ url: URL) async throws -> URLRequest {
    let accessToken = try await token()
    guard !accessToken.isEmpty, accessToken.utf8.count <= 2048,
      accessToken.utf8.allSatisfy({ (33...126).contains($0) })
    else { throw IssueTalkError.authenticationRequired }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("IssueTalk", forHTTPHeaderField: "User-Agent")
    return request
  }

  private func get(_ url: URL) async throws -> HTTPResponse {
    for attempt in 0..<3 {
      try Task.checkCancellation()
      let response: HTTPResponse
      do { response = try await transport.send(request(url)) } catch let error as URLError
        where attempt < 2 && error.code != .cancelled
      {
        try await sleep(.seconds(attempt + 1))
        continue
      }
      let limited =
        response.status == 429
        || (response.status == 403
          && (response.headers["x-ratelimit-remaining"] == "0"
            || response.headers["retry-after"] != nil))
      if limited && response.headers["retry-after"] == nil { throw IssueTalkError.rateLimited }
      let delay = Double(response.headers["retry-after"] ?? "") ?? Double(attempt + 1)
      if attempt < 2, [502, 503, 504].contains(response.status) || limited {
        guard delay >= 0, delay <= 5 else { throw IssueTalkError.rateLimited }
        try await sleep(.milliseconds(Int64(delay * 1_000)))
        continue
      }
      try Self.check(response)
      return response
    }
    throw IssueTalkError.invalidResponse
  }

  private static func check(_ response: HTTPResponse) throws {
    switch response.status {
    case 200..<300: return
    case 401: throw IssueTalkError.authenticationRequired
    case 403
    where response.headers["x-ratelimit-remaining"] == "0" || response.headers["retry-after"] != nil:
      throw IssueTalkError.rateLimited
    case 403: throw IssueTalkError.permissionDenied
    case 404: throw IssueTalkError.notFound
    case 429: throw IssueTalkError.rateLimited
    default: throw IssueTalkError.server(response.status)
    }
  }

  private static func nextPage(_ link: String?, path: String) throws -> URL? {
    guard let link else { return nil }
    for part in link.split(separator: ",") where part.contains("rel=\"next\"") {
      guard let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end,
        let url = URL(string: String(part[part.index(after: start)..<end])),
        url.scheme == "https", url.host == "api.github.com", url.port == nil,
        url.user == nil, url.password == nil, url.path == path, url.fragment == nil
      else { throw IssueTalkError.invalidResponse }
      return url
    }
    return nil
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
