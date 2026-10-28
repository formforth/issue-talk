import AVFoundation
import Foundation
import IssueTalkCore
import SwiftUI
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
  private var rendererHost: SnapshotWindowHost?
  func testNavigationDelegateMatchesSDKAndConfinesFiles() throws {
    let coordinator = MermaidWebView.Coordinator(failed: .constant(false))
    let index = try XCTUnwrap(
      Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Renderer"))
    coordinator.rendererURL = index
    XCTAssertTrue(
      coordinator.responds(
        to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
    XCTAssertTrue(coordinator.allowsNavigation(to: index))
    XCTAssertFalse(coordinator.allowsNavigation(to: URL(string: "https://example.com/index.html")))
    XCTAssertFalse(coordinator.allowsNavigation(to: URL(fileURLWithPath: "/tmp/index.html")))
    XCTAssertFalse(coordinator.allowsNavigation(to: nil))
  }

  func testFlowchartAndSequenceRenderOfflineWithSnapshot() async throws {
    defer {
      rendererHost?.close()
      rendererHost = nil
    }
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
    defer {
      rendererHost?.close()
      rendererHost = nil
    }
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
    let controller = UIViewController()
    controller.view = web
    rendererHost = SnapshotWindowHost(controller: controller, frame: web.frame)
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

@MainActor
final class MarkdownSnapshotTests: XCTestCase {
  func testNativeGFMLightAndDarkSnapshots() async throws {
    let source = """
      # Synthetic fixture
      **Strong** *emphasis* ~~removed~~ `inline` [Issue](https://github.com/test/repo/issues/1)

      - [x] Complete
      - [ ] Pending

      | Key | Value |
      | --- | --- |
      | Status | Synthetic |

      > Quoted context

      ```swift
      let count = 2
      ```
      """
    for theme in [ColorScheme.light, .dark] {
      let host = UIHostingController(
        rootView: ScrollView { MarkdownView(source: source).padding() }
          .preferredColorScheme(theme))
      let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
      let window = SnapshotWindowHost(controller: host, frame: bounds)
      defer { window.close() }
      try await Task.sleep(for: .milliseconds(300))
      host.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
        host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
      }
      XCTAssertEqual(image.size.width, 390)
      let attachment = XCTAttachment(image: image)
      attachment.name = "Native GFM \(theme)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }
}

/// Keep WebKit onscreen and restore the app's key window between snapshot tests.
@MainActor
private final class SnapshotWindowHost {
  private let window: UIWindow
  private weak var originalWindow: UIWindow?

  init(controller: UIViewController, frame: CGRect) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let original = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
    window = UIWindow(frame: frame)
    window.windowScene = original?.windowScene ?? scenes.first
    window.frame = frame
    window.rootViewController = controller
    originalWindow = original
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
  }

  func close() {
    window.isHidden = true
    originalWindow?.makeKeyAndVisible()
  }
}
