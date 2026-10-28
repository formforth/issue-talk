import Foundation

public struct Workspace: Codable, Sendable {
  public var issues: [MonitoredIssue] = []
  public var turns: [ConversationTurn] = []
  public var discussionIssueID: Int64?
  public var contextSummary = ""
  public init() {}

  enum CodingKeys: String, CodingKey { case issues, turns, discussionIssueID, contextSummary }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    issues = try values.decode([MonitoredIssue].self, forKey: .issues)
    turns = try values.decodeIfPresent([ConversationTurn].self, forKey: .turns) ?? []
    discussionIssueID = try values.decodeIfPresent(Int64.self, forKey: .discussionIssueID)
    contextSummary = try values.decodeIfPresent(String.self, forKey: .contextSummary) ?? ""
  }

  public var monitored: [MonitoredIssue] { issues.filter(\.monitoring) }
  public var unread: [MonitoredIssue] { monitored.filter(\.isUnread) }

  public func visibleTurns(issueID: Int64?) -> [ConversationTurn] {
    guard let issueID else { return turns }
    return turns.filter { $0.issueIDs.contains(issueID) }
  }

  /// Associations are user-correctable context, never authorization to post.
  public mutating func appendTurn(_ turn: ConversationTurn) throws {
    guard Set(turn.issueIDs).isSubset(of: Set(issues.map(\.id))),
      !turn.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw IssueTalkError.invalidResponse }
    turns.append(turn)
  }

  public mutating func correctLinks(turnID: UUID, issueIDs: Set<Int64>) throws {
    guard issueIDs.isSubset(of: Set(issues.map(\.id))),
      let index = turns.firstIndex(where: { $0.id == turnID })
    else { throw IssueTalkError.notFound }
    turns[index].issueIDs = issueIDs
  }

  /// Bounded local context. Older history remains on disk; the user maintains its summary.
  public func context(maxCharacters: Int = 12_000) -> String {
    guard maxCharacters > 0 else { return "" }
    var lines: [String] = []
    var remaining = maxCharacters
    for turn in turns.reversed() {
      let value = "\(turn.role.rawValue): \(turn.body)"
      guard value.count <= remaining else { break }
      lines.append(value)
      remaining -= value.count + 1
    }
    let summary = String(contextSummary.prefix(max(0, remaining)))
    return ([summary] + lines.reversed()).filter { !$0.isEmpty }.joined(separator: "\n")
  }
}

public struct ConversationTurn: Codable, Identifiable, Sendable {
  public enum Role: String, Codable, Sendable { case user, assistant, event }
  public let id: UUID
  public let role: Role
  public let body: String
  public let createdAt: Date
  public var issueIDs: Set<Int64>

  public init(
    id: UUID = UUID(), role: Role, body: String, createdAt: Date = Date(),
    issueIDs: Set<Int64> = []
  ) {
    self.id = id
    self.role = role
    self.body = body
    self.createdAt = createdAt
    self.issueIDs = issueIDs
  }
}

extension MonitoredIssue {
  /// Stable across processes and devices; Swift's randomized Hasher must not choose UI colors.
  public var colorIndex: Int {
    let value = identity.url.absoluteString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
      ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    return Int(value % 6)
  }
}
