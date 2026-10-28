import Foundation

public enum IssueTalkError: Error, Equatable, Sendable {
  case invalidIssueURL
  case invalidResponse
  case invalidComment
  case authenticationRequired
  case permissionDenied
  case notFound
  case rateLimited
  case server(Int)
  case duplicateOperation
  case uncertainWrite
}

public struct IssueIdentity: Hashable, Codable, Sendable {
  public let owner: String
  public let repository: String
  public let number: Int64

  public init(url: URL) throws {
    let components = url.path.split(separator: "/").map(String.init)
    guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
      url.user == nil, url.password == nil, url.port == nil || url.port == 443,
      components.count == 4, components[2] == "issues",
      let number = Int64(components[3]), number > 0,
      components[0].range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil,
      components[1].range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
      ![".", ".."].contains(components[1])
    else { throw IssueTalkError.invalidIssueURL }
    owner = components[0].lowercased()
    repository = components[1].lowercased()
    self.number = number
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let url = try container.decode(URL.self)
    try self.init(url: url)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(url)
  }

  public var url: URL {
    // All components were validated before constructing the canonical URL.
    URL(string: "https://github.com/\(owner)/\(repository)/issues/\(number)")!
  }

  public var apiPath: String { "/repos/\(owner)/\(repository)/issues/\(number)" }
}

public struct GitHubIssue: Codable, Equatable, Sendable {
  public let id: Int64
  public let number: Int64
  public let title: String
  public let body: String?
  public let htmlURL: URL
  public let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id, number, title, body
    case htmlURL = "html_url"
    case updatedAt = "updated_at"
  }
}

public struct GitHubComment: Codable, Equatable, Identifiable, Sendable {
  public let id: Int64
  public let body: String
  public let htmlURL: URL
  public let createdAt: Date
  public let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id, body
    case htmlURL = "html_url"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
