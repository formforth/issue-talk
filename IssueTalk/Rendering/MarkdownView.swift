import IssueTalkCore
import SwiftUI

struct MarkdownView: View {
  let source: String
  @State private var document: GFMDocument?
  @State private var showSource = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showSource {
        Text(source).font(.system(.body, design: .monospaced)).textSelection(.enabled)
      } else if let document {
        ForEach(document.nodes) { node in MarkdownBlock(node: node) }
        if document.truncated { Text("Preview limited. View source for the complete Markdown.") }
      } else {
        Text("Preparing Markdown…").foregroundStyle(.secondary)
      }
      Button(showSource ? "Render Markdown" : "View source") { showSource.toggle() }.font(.caption)
    }
    .task(id: source) {
      let value = source
      let parsed = await Task.detached(priority: .userInitiated) { GFMDocument(source: value) }
        .value
      guard !Task.isCancelled else { return }
      document = parsed
    }
  }
}

private struct MarkdownBlock: View {
  let node: GFMNode

  var body: some View {
    switch node.kind {
    case .paragraph, .cell:
      Text(inline(node)).textSelection(.enabled)
    case .heading(let level):
      Text(inline(node)).font(level == 1 ? .title2 : .headline).textSelection(.enabled)
    case .code(let language):
      VStack(alignment: .leading) {
        Text(language.isEmpty ? "Code" : language).font(.caption).foregroundStyle(.secondary)
        ScrollView(.horizontal) {
          Text(node.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
      }.padding(8).background(Color.secondary.opacity(0.1))
    case .mermaid: MermaidView(source: node.text)
    case .rule: Divider()
    case .quote:
      HStack(alignment: .top) {
        Rectangle().fill(.secondary).frame(width: 3)
        children
      }
    case .item(let marker):
      HStack(alignment: .top) {
        Text(marker)
        children
      }
    case .table:
      ScrollView(.horizontal) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
          ForEach(rows(node)) { row in
            GridRow { ForEach(row.children) { cell in Text(inline(cell)).textSelection(.enabled) } }
          }
        }.padding(8).background(Color.secondary.opacity(0.08))
      }
    case .text, .emphasis, .strong, .strike, .inlineCode, .link:
      Text(inline(node)).textSelection(.enabled)
    default: children
    }
  }

  private var children: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(node.children) { child in AnyView(MarkdownBlock(node: child)) }
    }
  }

  private func rows(_ node: GFMNode) -> [GFMNode] {
    node.children.flatMap { $0.kind == .row ? [$0] : rows($0) }
  }

  private func inline(_ node: GFMNode) -> AttributedString {
    var value = AttributedString(node.text)
    for child in node.children { value += inline(child) }
    switch node.kind {
    case .emphasis: value.font = .body.italic()
    case .strong: value.font = .body.bold()
    case .strike: value.strikethroughStyle = .single
    case .inlineCode: value.font = .system(.body, design: .monospaced)
    case .link(let destination): value.link = GFMDocument.externalURL(destination)
    default: break
    }
    return value
  }
}
