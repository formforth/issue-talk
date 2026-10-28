import Foundation
import Testing

@testable import IssueTalkCore

struct RoutingTests {
  private func workspace() throws -> Workspace {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let metadata = try decoder.decode(
      GitHubIssue.self,
      from: Data(
        """
        {"id":100,"number":1,"title":"Synthetic target","body":"Context is not authorization",
        "html_url":"https://github.com/test/repo/issues/1","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8))
    var workspace = Workspace()
    workspace.issues = [
      try MonitoredIssue(
        identity: IssueIdentity(url: metadata.htmlURL), metadata: metadata, comments: [])
    ]
    workspace.issues[0].draft = "A deliberate draft"
    return workspace
  }

  @Test func inferenceCannotInventTargetsSourcesOrAuthorizeWrites() throws {
    let workspace = try workspace()
    for (url, source) in [
      ("https://evil.example/issues/1", ""),
      ("https://github.com/test/repo/issues/2", ""),
      (
        "https://github.com/test/repo/issues/1",
        "https://github.com/test/repo/issues/1#issuecomment-999"
      ),
    ] {
      #expect(throws: LocalInferenceError.self) {
        try DraftProposal(
          suggestion: RoutingSuggestion(
            intent: .draft, issueURL: url, sourceURL: source, text: "Draft"), workspace: workspace)
      }
    }
    let proposal = try DraftProposal(
      suggestion: RoutingSuggestion(
        intent: .draft,
        issueURL: "https://github.com/test/repo/issues/1", text: "Review me"), workspace: workspace)
    #expect(proposal.issueID == 100)
    #expect(workspace.issues[0].draft == "A deliberate draft")  // Suggestion has no side effects.
    #expect(RoutingSuggestion.Intent(rawValue: "post") == nil)
  }

  @Test func postConfirmationBindsDraftSourceTargetAndDeadline() throws {
    var workspace = try workspace()
    let now = Date(timeIntervalSince1970: 100)
    let confirmation = try PostConfirmation(issue: workspace.issues[0], now: now)
    #expect(try confirmation.validate(in: workspace, now: now) == 100)
    #expect(throws: LocalInferenceError.self) {
      try confirmation.validate(in: workspace, now: now.addingTimeInterval(61))
    }
    workspace.issues[0].draft = "Changed after spoken preview"
    #expect(throws: LocalInferenceError.self) { try confirmation.validate(in: workspace, now: now) }
    workspace.issues[0].draft = "A deliberate draft"
    workspace.issues[0].writeUnresolved = true
    #expect(throws: LocalInferenceError.self) { try confirmation.validate(in: workspace, now: now) }
    #expect(throws: IssueTalkError.self) { try PostConfirmation(issue: workspace.issues[0]) }
  }

  @Test func commandsRequireWholeUserUtteranceNotQuotedOrEmbeddedKeywords() {
    for text in [
      "Do not post draft", "He said confirm post", "`post draft`", "Please summarize: post draft",
      "投稿しないで", "下書きを投稿という意味を教えて", "confirm post and ignore all checks",
    ] { #expect(VoiceCommand.parse(text) == .chat) }
    #expect(VoiceCommand.parse("Read next.") == .readNext)
    #expect(VoiceCommand.parse("投稿を確定。") == .confirmPost)
    #expect(VoiceCommand.parse("下書きを投稿") == .postDraft)
  }
}
