import SwiftUI
import WebKit

struct MermaidView: View {
  let source: String
  @State private var showSource = false
  @State private var fullscreen = false
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading) {
      if showSource || failed {
        Text(source).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        if failed { Text("Diagram unavailable. Original source is shown.").font(.caption) }
      } else {
        MermaidWebView(source: source, failed: $failed).frame(height: 260)
      }
      HStack {
        Button(showSource ? "Diagram" : "Source") { showSource.toggle() }
        Button("Copy source") { UIPasteboard.general.string = source }
        Button("Enlarge") { fullscreen = true }
      }.font(.caption)
    }
    .onChange(of: source) { _, _ in failed = false }
    .sheet(isPresented: $fullscreen) {
      NavigationStack {
        MermaidWebView(source: source, failed: $failed)
          .navigationTitle("Diagram")
          .toolbar { Button("Done") { fullscreen = false } }
      }
    }
  }
}

struct MermaidWebView: UIViewRepresentable {
  @Environment(\.colorScheme) private var colorScheme
  let source: String
  @Binding var failed: Bool

  func makeCoordinator() -> Coordinator { Coordinator(failed: $failed) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    let web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = context.coordinator
    web.isOpaque = false
    web.scrollView.minimumZoomScale = 0.25
    web.scrollView.maximumZoomScale = 5
    if let index = Bundle.main.url(
      forResource: "index", withExtension: "html", subdirectory: "Renderer")
    {
      context.coordinator.rendererURL = index
      web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    } else {
      context.coordinator.failed.wrappedValue = true
    }
    return web
  }

  func updateUIView(_ web: WKWebView, context: Context) {
    context.coordinator.render(web, source: source, dark: colorScheme == .dark)
  }

  @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
    var failed: Binding<Bool>
    var rendererURL: URL?
    private var loaded = false
    private var source = ""
    private var dark = false
    private var rendered = ""

    init(failed: Binding<Bool>) { self.failed = failed }

    func render(_ web: WKWebView, source: String, dark: Bool) {
      self.source = source
      self.dark = dark
      let key = "\(dark):\(source)"
      guard loaded, rendered != key else { return }
      rendered = key
      web.callAsyncJavaScript(
        "return await window.renderDiagram(source, dark);",
        arguments: ["source": source, "dark": dark], in: nil, contentWorld: .page
      ) { [weak self] result in
        if case .failure = result, self?.rendered == key { self?.failed.wrappedValue = true }
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      loaded = true
      render(webView, source: source, dark: dark)
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      decisionHandler(allowsNavigation(to: action.request.url) ? .allow : .cancel)
    }

    func allowsNavigation(to url: URL?) -> Bool {
      url != nil && url == rendererURL
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) { failed.wrappedValue = true }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      failed.wrappedValue = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      failed.wrappedValue = true
    }
  }
}
