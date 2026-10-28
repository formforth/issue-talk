import AVFoundation
import Foundation
import IssueTalkCore
import WebKit
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

// WebKit runs the pinned renderer without access to any remote asset.
@MainActor
final class MermaidRenderingTests: XCTestCase {
  func testFlowchartAndSequenceRenderOfflineWithSnapshot() async throws {
    let web = try await loadedRenderer()
    for source in ["flowchart LR\n A --> B", "sequenceDiagram\n Alice->>Bob: Synthetic message"] {
      let value = try await web.callAsyncJavaScript(
        "await window.renderDiagram(source, dark); return document.querySelector('#diagram svg') !== null;",
        arguments: ["source": source, "dark": true], in: nil, contentWorld: .page)
      XCTAssertEqual(value as? Bool, true)
    }
    let image = try await web.takeSnapshot(configuration: nil)
    XCTAssertGreaterThan(image.size.width, 0)
    let attachment = XCTAttachment(image: image)
    attachment.name = "Offline Mermaid sequence, dark mode"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testDiagramConfigurationInjectionAndInvalidSyntaxFail() async throws {
    let web = try await loadedRenderer()
    for source in ["%%{init: {securityLevel: 'loose'}}%%\nflowchart LR\n A-->B", "not a diagram"] {
      do {
        _ = try await web.callAsyncJavaScript(
          "return await window.renderDiagram(source, false);",
          arguments: ["source": source], in: nil, contentWorld: .page)
        XCTFail("Untrusted or invalid source must fail")
      } catch { /* The UI shows the original source on render errors. */  }
    }
  }

  private func loadedRenderer() async throws -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 300), configuration: config)
    let index = try XCTUnwrap(
      Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Renderer"))
    web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    for _ in 0..<100 {
      if let ready = try? await web.evaluateJavaScript(
        "typeof window.renderDiagram === 'function' && typeof mermaid !== 'undefined'"),
        ready as? Bool == true
      {
        return web
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw NSError(domain: "RendererNotReady", code: 1)
  }
}
