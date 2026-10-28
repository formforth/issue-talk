import Foundation
import Testing

@testable import IssueTalkCore

struct MarkdownTests {
  private func flatten(_ nodes: [GFMNode]) -> [GFMNode] {
    nodes.flatMap { [$0] + flatten($0.children) }
  }

  @Test func parsesGFMWithoutExecutingHTMLOrLoadingImages() {
    let source = """
      # Heading
      **Strong** *emphasis* ~~deleted~~ `inline` [Issue](https://github.com/test/repo/issues/1)

      - [x] Done
      - [ ] Pending

      | Key | Value |
      | --- | --- |
      | A | B |

      > Quoted

      ```swift
      let value = 1
      ```

      ```mermaid
      flowchart LR
        A --> B
      ```

      ![Tracking image](https://example.com/pixel.png)

      <script>alert('untrusted')</script>
      """
    let nodes = flatten(GFMDocument(source: source).nodes)
    for kind: GFMNode.Kind in [
      .heading(1), .strong, .emphasis, .strike, .inlineCode,
      .item("☑"), .item("☐"), .table, .quote, .code("swift"), .mermaid, .code("html"),
    ] { #expect(nodes.contains { $0.kind == kind }) }
    #expect(nodes.contains { $0.text.contains("Tracking image") })
    #expect(nodes.contains { $0.text.contains("alert('untrusted')") })
  }

  @Test func linkPolicyRejectsScriptsCredentialsAndLocalFiles() {
    for url in [
      "javascript:alert(1)", "file:///etc/passwd", "data:text/html,test",
      "https://token@example.com", "issuetalk://oauth/callback",
    ] { #expect(GFMDocument.externalURL(url) == nil) }
    #expect(GFMDocument.externalURL("https://github.com/test/repo/issues/1#issuecomment-10") != nil)
  }

  @Test func malformedAndLargeDocumentsHaveBoundedPreviewsAndStableIDs() {
    let source = "```unknown\n<unclosed " + String(repeating: "x", count: 200_001)
    let first = GFMDocument(source: source)
    #expect(first.truncated)
    #expect(first.nodes.map(\.id) == GFMDocument(source: source).nodes.map(\.id))
    #expect(flatten(first.nodes).map(\.text).joined().count <= 200_000)
  }
}
