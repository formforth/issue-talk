import Foundation

public enum OAuthError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidCallback
  case authorizationFailed
}

public struct OAuthConfiguration: Sendable {
  public let clientID: String
  public let redirectURI: URL
  public let broker: URL

  public init(clientID: String, redirectURI: URL, broker: URL) throws {
    guard !clientID.isEmpty, redirectURI.scheme == "issuetalk", redirectURI.host == "oauth",
      redirectURI.path == "/callback", redirectURI.query == nil, redirectURI.fragment == nil,
      redirectURI.user == nil, redirectURI.password == nil, redirectURI.port == nil,
      broker.scheme == "https", broker.host != nil, broker.user == nil, broker.password == nil,
      broker.query == nil, broker.fragment == nil
    else { throw OAuthError.invalidConfiguration }
    self.clientID = clientID
    self.redirectURI = redirectURI
    self.broker = broker
  }

  public func authorizationURL(state: String, challenge: String) -> URL {
    var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
      URLQueryItem(name: "scope", value: "repo"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components.url!
  }

  public func code(from callback: URL, expectedState: String) throws -> String {
    guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      components.scheme == redirectURI.scheme, components.host == redirectURI.host,
      components.path == redirectURI.path, components.port == nil, components.user == nil,
      components.password == nil, components.fragment == nil
    else { throw OAuthError.invalidCallback }
    let items = components.queryItems ?? []
    let states = items.filter { $0.name == "state" }
    let codes = items.filter { $0.name == "code" }
    guard !expectedState.isEmpty, states.count == 1, states[0].value == expectedState,
      codes.count == 1, let code = codes[0].value, !code.isEmpty,
      !items.contains(where: { $0.name == "error" })
    else { throw OAuthError.invalidCallback }
    return code
  }
}

public struct OAuthTokens: Codable, Sendable {
  public let accessToken: String
  public let refreshToken: String?
  public let expiresAt: Date?

  public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
  }
}

public struct Workspace: Codable, Sendable {
  public var issues: [MonitoredIssue] = []
  public init() {}
}

public struct MonitoredIssue: Codable, Identifiable, Sendable {
  public var id: Int64 { metadata.id }
  public let identity: IssueIdentity
  public var metadata: GitHubIssue
  public var comments: [GitHubComment]
  public var draft: String = ""
  public var replySource: URL?
  public var operationID: UUID?
  /// Persisted before dispatch. After a restart, an unresolved write is never auto-retried.
  public var writeUnresolved = false
  public var postedCommentURL: URL?

  public init(identity: IssueIdentity, metadata: GitHubIssue, comments: [GitHubComment]) {
    self.identity = identity
    self.metadata = metadata
    self.comments = comments
  }

  public func commentBody() throws -> String {
    let text = draft
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw IssueTalkError.invalidComment
    }
    let body: String
    if let source = replySource {
      guard comments.contains(where: { $0.htmlURL == source }) else {
        throw IssueTalkError.invalidResponse
      }
      body = "In reply to \(source.absoluteString)\n\n\(text)"
    } else {
      body = text
    }
    guard body.utf8.count <= 65_536 else { throw IssueTalkError.invalidComment }
    return body
  }
}
