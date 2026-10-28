import Foundation

public struct TimelineEntry: Identifiable, Sendable {
  public let id: String
  public let role: ConversationTurn.Role
  public let body: String
  public let createdAt: Date
  public let issueIDs: Set<Int64>
  public let localTurnID: UUID?
  public let sourceURL: URL?
}

extension Workspace {
  public func timeline(issueID: Int64?) -> [TimelineEntry] {
    var entries = turns.map {
      TimelineEntry(
        id: $0.id.uuidString, role: $0.role, body: $0.body,
        createdAt: $0.createdAt, issueIDs: $0.issueIDs, localTurnID: $0.id, sourceURL: nil)
    }
    for issue in issues {
      entries.append(
        TimelineEntry(
          id: "issue-\(issue.id)", role: .event,
          body: "# \(issue.metadata.title)\n\n\(issue.metadata.body ?? "")",
          createdAt: issue.metadata.createdAt ?? issue.metadata.updatedAt,
          issueIDs: [issue.id], localTurnID: nil, sourceURL: issue.identity.url))
      entries += issue.comments.map {
        TimelineEntry(
          id: "comment-\($0.id)", role: .event, body: $0.body,
          createdAt: $0.createdAt, issueIDs: [issue.id], localTurnID: nil, sourceURL: $0.htmlURL)
      }
    }
    return entries.filter { issueID == nil || $0.issueIDs.contains(issueID!) }
      .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
  }
}
