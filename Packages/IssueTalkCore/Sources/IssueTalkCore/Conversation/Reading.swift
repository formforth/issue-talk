import Foundation

public struct ReadCursor: Codable, Equatable, Sendable {
  public struct CommentVersion: Codable, Equatable, Sendable {
    public let id: Int64
    public let updatedAt: Date
  }
  public let issueUpdatedAt: Date
  public let comments: [CommentVersion]

  public init(issue: MonitoredIssue) {
    issueUpdatedAt = issue.metadata.updatedAt
    comments = issue.comments.map { CommentVersion(id: $0.id, updatedAt: $0.updatedAt) }
      .sorted { $0.id < $1.id }
  }
}

public struct ReadingSession: Sendable, Identifiable {
  public let id = UUID()
  public let issueID: Int64
  public let cursor: ReadCursor
  public let text: String

  public init(issue: MonitoredIssue) {
    issueID = issue.id
    cursor = ReadCursor(issue: issue)
    let previous = issue.readCursor?.comments ?? []
    let updates = issue.comments.filter { comment in
      !previous.contains { $0.id == comment.id && $0.updatedAt == comment.updatedAt }
    }
    let excerpts = updates.suffix(5).map { String($0.body.prefix(600)) }
    let detail =
      excerpts.isEmpty
      ? String((issue.metadata.body ?? "").prefix(600))
      : excerpts.joined(separator: "\n\n")
    text = """
      \(issue.identity.owner)/\(issue.identity.repository), Issue \(issue.identity.number): \(issue.metadata.title).
      \(updates.count) new or updated comments. \(detail)
      Would you like to post a reply?
      """
  }
}

extension MonitoredIssue {
  public var isUnread: Bool { readCursor != ReadCursor(issue: self) }
}

extension Workspace {
  public func nextReading() -> ReadingSession? {
    // Registration order is stable; no unsolicited selection or advancement.
    unread.first.map(ReadingSession.init)
  }

  public mutating func completeReading(_ session: ReadingSession) throws {
    guard let index = issues.firstIndex(where: { $0.id == session.issueID }) else {
      throw IssueTalkError.notFound
    }
    guard issues[index].readCursor != session.cursor else { return }
    // A poll arriving during speech must not mark the newly arrived content as read.
    issues[index].readCursor = session.cursor
    discussionIssueID = session.issueID
    try appendTurn(
      ConversationTurn(role: .assistant, body: session.text, issueIDs: [session.issueID]))
  }
}
