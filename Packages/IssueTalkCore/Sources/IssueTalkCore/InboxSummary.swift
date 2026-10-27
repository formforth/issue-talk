/// An issue-level unread count; repeated updates to an issue count only once.
public struct InboxSummary: Equatable, Sendable {
  public let unreadIssueCount: Int

  public init(unreadIssueIDs: [Int64]) {
    unreadIssueCount = Set(unreadIssueIDs).count
  }
}
