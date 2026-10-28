import Foundation
import Markdown

public struct GFMNode: Sendable, Identifiable {
  public enum Kind: Sendable, Equatable {
    case container, paragraph
    case heading(Int)
    case quote, list
    case item(String)
    case table, row, cell
    case code(String)
    case mermaid, rule, text, emphasis, strong, strike, inlineCode
    case link(String)
  }
  public let id: String
  public var kind: Kind
  public var text = ""
  public var children: [GFMNode] = []
}

public struct GFMDocument: Sendable {
  public let nodes: [GFMNode]
  public let truncated: Bool

  public init(source: String) {
    truncated = source.count > 200_000
    let document = Document(parsing: String(source.prefix(200_000)))
    nodes = document.children.enumerated().prefix(1_500).map {
      Self.convert($0.element, id: String($0.offset), depth: 0)
    }
  }

  public static func externalURL(_ value: String) -> URL? {
    guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased()),
      url.host != nil, url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  private static func convert(_ markup: any Markup, id: String, depth: Int) -> GFMNode {
    guard depth < 32 else { return GFMNode(id: id, kind: .text, text: "[Nested content omitted]") }
    if let leaf = leaf(markup, id: id) { return leaf }
    var node = GFMNode(id: id, kind: blockKind(markup))
    node.children = markup.children.enumerated().prefix(1_500).map {
      convert($0.element, id: "\(id).\($0.offset)", depth: depth + 1)
    }
    return node
  }

  private static func leaf(_ markup: any Markup, id: String) -> GFMNode? {
    switch markup {
    case let text as Markdown.Text: return GFMNode(id: id, kind: .text, text: text.string)
    case let code as InlineCode: return GFMNode(id: id, kind: .inlineCode, text: code.code)
    case let code as CodeBlock:
      let language = code.language ?? ""
      let kind: GFMNode.Kind = language.lowercased() == "mermaid" ? .mermaid : .code(language)
      return GFMNode(id: id, kind: kind, text: code.code)
    case let image as Markdown.Image:
      return GFMNode(id: id, kind: .text, text: "[Image: \(image.plainText)]")
    case let html as HTMLBlock: return GFMNode(id: id, kind: .code("html"), text: html.rawHTML)
    case let html as InlineHTML: return GFMNode(id: id, kind: .text, text: html.rawHTML)
    case is SoftBreak, is LineBreak: return GFMNode(id: id, kind: .text, text: "\n")
    default: return nil
    }
  }

  private static func blockKind(_ markup: any Markup) -> GFMNode.Kind {
    switch markup {
    case let heading as Heading: return .heading(heading.level)
    case is Paragraph: return .paragraph
    case is BlockQuote: return .quote
    case is OrderedList, is UnorderedList: return .list
    case let item as ListItem: return .item(listMarker(item))
    case is Table: return .table
    case is ThematicBreak: return .rule
    default: return inlineKind(markup)
    }
  }

  private static func inlineKind(_ markup: any Markup) -> GFMNode.Kind {
    switch markup {
    case is Table.Head, is Table.Row: return .row
    case is Table.Cell: return .cell
    case is Emphasis: return .emphasis
    case is Strong: return .strong
    case is Strikethrough: return .strike
    case let link as Markdown.Link: return .link(link.destination ?? "")
    default: return .container
    }
  }

  private static func listMarker(_ item: ListItem) -> String {
    if let checkbox = item.checkbox { return checkbox == .checked ? "☑" : "☐" }
    if let list = item.parent as? OrderedList {
      return "\(Int(list.startIndex) + item.indexInParent)."
    }
    return "•"
  }
}
