import AVFoundation
import Foundation
import IssueTalkCore
import XCTest

@testable import IssueTalk

final class IssueTalkTests: XCTestCase {
  @MainActor
  func testOwnAudioCategoryTransitionDoesNotCancelReading() {
    let category = Notification(
      name: AVAudioSession.routeChangeNotification,
      userInfo: [
        AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue
      ])
    let unplug = Notification(
      name: AVAudioSession.routeChangeNotification,
      userInfo: [
        AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable
          .rawValue
      ])
    XCTAssertFalse(ReadingSpeaker.isExternalRouteChange(category))
    XCTAssertTrue(ReadingSpeaker.isExternalRouteChange(unplug))
  }

  func testUnreadCountUsesIssueIdentity() {
    XCTAssertEqual(InboxSummary(unreadIssueIDs: [101, 101, 202]).unreadIssueCount, 2)
  }
  func testShareQueueKeepsIndependentReceiptsAndCanonicalIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = SharedIssueQueue(directory: directory)
    let identity = try IssueIdentity(
      url: XCTUnwrap(URL(string: "https://github.com/Test/Repo/issues/1?tracking=ignored")))
    try queue.enqueue(identity)
    try queue.enqueue(identity)
    let pending = try queue.pending()
    XCTAssertEqual(pending.count, 2)
    XCTAssertEqual(Set(pending.map(\.id)).count, 2)
    XCTAssertEqual(pending[0].identity.url.absoluteString, "https://github.com/test/repo/issues/1")
    try queue.remove(pending[0])
    XCTAssertEqual(try queue.pending().count, 1)
  }

  func testMalformedShareReceiptDoesNotDeleteOtherPendingURLs() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = SharedIssueQueue(directory: directory)
    try queue.enqueue(
      IssueIdentity(url: XCTUnwrap(URL(string: "https://github.com/test/repo/issues/1"))))
    try Data("{}".utf8).write(to: directory.appendingPathComponent("invalid.json"))
    XCTAssertThrowsError(try queue.pending())
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
  }
}
