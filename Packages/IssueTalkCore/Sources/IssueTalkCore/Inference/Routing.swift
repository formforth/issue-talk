import Foundation

public enum LocalInferenceError: Error, Sendable {
  case unavailable
  case invalidSuggestion
}

public struct RoutingSuggestion: Codable, Sendable {
  public enum Intent: String, Codable, Sendable { case chat, readNext, switchIssue, draft }
  public let intent: Intent
  public let issueURL: String
  public let sourceURL: String
  public let text: String

  public init(intent: Intent, issueURL: String = "", sourceURL: String = "", text: String = "") {
    self.intent = intent
    self.issueURL = issueURL
    self.sourceURL = sourceURL
    self.text = text
  }
}

public protocol LocalInferenceEngine: Sendable {
  func suggest(userText: String, context: String, issueURLs: [String]) async throws
    -> RoutingSuggestion
}

public struct DraftProposal: Sendable {
  public let issueID: Int64
  public let issueURL: URL
  public let sourceURL: URL?
  public let text: String

  public init(suggestion: RoutingSuggestion, workspace: Workspace) throws {
    guard suggestion.intent == .draft,
      let url = URL(string: suggestion.issueURL), let identity = try? IssueIdentity(url: url),
      let item = workspace.monitored.first(where: { $0.identity == identity }),
      !item.writeUnresolved
    else { throw LocalInferenceError.invalidSuggestion }
    var preview = item
    if suggestion.sourceURL.isEmpty {
      preview.replySource = nil
    } else {
      guard let source = URL(string: suggestion.sourceURL),
        item.comments.contains(where: { $0.htmlURL == source })
      else { throw LocalInferenceError.invalidSuggestion }
      preview.replySource = source
    }
    preview.draft = suggestion.text
    _ = try preview.commentBody()
    issueID = item.id
    issueURL = item.identity.url
    sourceURL = preview.replySource
    text = preview.draft
  }
}

public enum VoiceCommand: String, Codable, Sendable {
  case readNext, stop, postDraft, confirmPost, acceptSuggestion, cancel, chat

  public static func parse(_ text: String) -> VoiceCommand {
    switch text.trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。!?！？"))
    ).lowercased() {
    case "read next", "next issue", "次を読む", "次のイシュー": return .readNext
    case "stop", "stop reading", "停止", "止めて": return .stop
    case "post draft", "下書きを投稿": return .postDraft
    case "confirm post", "投稿を確定": return .confirmPost
    case "accept suggestion", "提案を採用": return .acceptSuggestion
    case "cancel", "キャンセル": return .cancel
    default: return .chat
    }
  }
}

/// Explicit two-step authorization is separate from inference, filters and content links.
public struct PostConfirmation: Sendable {
  public let issueURL: URL
  public let issueID: Int64
  public let body: String
  public let expiresAt: Date

  public init(issue: MonitoredIssue, now: Date = Date()) throws {
    guard !issue.writeUnresolved else { throw IssueTalkError.uncertainWrite }
    issueID = issue.id
    issueURL = issue.identity.url
    body = try issue.commentBody()
    expiresAt = now.addingTimeInterval(60)
  }

  public func validate(in workspace: Workspace, now: Date = Date()) throws -> Int64 {
    guard now < expiresAt, let issue = workspace.monitored.first(where: { $0.id == issueID }),
      issue.identity.url == issueURL, !issue.writeUnresolved, try issue.commentBody() == body
    else { throw LocalInferenceError.invalidSuggestion }
    return issueID
  }
}
