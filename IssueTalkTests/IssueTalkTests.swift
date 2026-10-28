import AVFoundation
import IssueTalkCore
import XCTest

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
}
