import IssueTalkCore
import XCTest

final class IssueTalkTests: XCTestCase {
  func testUnreadCountUsesIssueIdentity() {
    XCTAssertEqual(InboxSummary(unreadIssueIDs: [101, 101, 202]).unreadIssueCount, 2)
  }
}
