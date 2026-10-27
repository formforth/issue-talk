import Testing

@testable import IssueTalkCore

struct InboxSummaryTests {
  @Test func emptyInboxHasNoUnreadIssues() {
    #expect(InboxSummary(unreadIssueIDs: []).unreadIssueCount == 0)
  }

  @Test func repeatedUpdatesCountAsOneUnreadIssue() {
    #expect(InboxSummary(unreadIssueIDs: [101, 101, 202]).unreadIssueCount == 2)
  }
}
