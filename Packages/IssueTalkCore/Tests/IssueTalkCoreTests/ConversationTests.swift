import Foundation
import Testing

@testable import IssueTalkCore

struct ConversationTests {
  private func item(id: Int64 = 100, number: Int64 = 1, body: String = "Original") throws
    -> MonitoredIssue
  {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let issue = try decoder.decode(
      GitHubIssue.self,
      from: Data(
        """
        {"id":\(id),"number":\(number),"title":"Synthetic issue","body":"\(body)",
        "html_url":"https://github.com/test/repo/issues/\(number)","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8))
    return try MonitoredIssue(
      identity: IssueIdentity(url: issue.htmlURL), metadata: issue, comments: [])
  }

  private func comment(id: Int64) throws -> GitHubComment {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      GitHubComment.self,
      from: Data(
        """
        {"id":\(id),"body":"Synthetic update","html_url":"https://github.com/test/repo/issues/1#issuecomment-\(id)",
        "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8))
  }

  @Test func migratesOriginalWorkspaceWithoutLosingUnresolvedDrafts() throws {
    var original = try item()
    original.draft = "Retain whitespace\n\n"
    original.writeUnresolved = true
    original.operationID = UUID()
    let data = try JSONEncoder().encode(original)
    var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    fields.removeValue(forKey: "monitoring")
    fields.removeValue(forKey: "readCursor")
    let legacy = try JSONSerialization.data(withJSONObject: ["issues": [fields]])
    let restored = try JSONDecoder().decode(Workspace.self, from: legacy)
    #expect(restored.issues[0].monitoring)
    #expect(restored.issues[0].writeUnresolved)
    #expect(restored.issues[0].operationID == original.operationID)
    #expect(restored.issues[0].draft == original.draft)
    #expect(restored.turns.isEmpty)
  }

  @Test func readCompletesOnlyCapturedRevisionAndDoesNotAdvance() throws {
    var workspace = Workspace()
    workspace.issues = [try item(), try item(id: 200, number: 2)]
    let reading = try #require(workspace.nextReading())
    #expect(workspace.unread.count == 2)  // Selection/interruption alone changes nothing.
    workspace.issues[0].comments.append(try comment(id: 10))
    try workspace.completeReading(reading)
    #expect(workspace.unread.count == 2)
    #expect(workspace.discussionIssueID == 100)
    let secondReading = try #require(workspace.nextReading())
    #expect(secondReading.issueID == 100)
    try workspace.completeReading(secondReading)
    #expect(workspace.unread.map(\.id) == [200])
    #expect(workspace.discussionIssueID == 100)
    workspace.issues[1].monitoring = false
    #expect(workspace.nextReading() == nil)
    #expect(workspace.issues.count == 2)
  }

  @Test func filtersAndCorrectionsDoNotChangeReplyTargetsOrDiscussion() throws {
    var workspace = Workspace()
    workspace.issues = [try item(), try item(id: 200, number: 2)]
    workspace.issues[0].replySource = URL(
      string: "https://github.com/test/repo/issues/1#issuecomment-10")
    workspace.discussionIssueID = 100
    let unrelated = ConversationTurn(role: .user, body: "Unrelated")
    let multi = ConversationTurn(role: .assistant, body: "Across both", issueIDs: [100, 200])
    try workspace.appendTurn(unrelated)
    try workspace.appendTurn(multi)
    #expect(workspace.visibleTurns(issueID: nil).count == 2)
    #expect(workspace.visibleTurns(issueID: 200).map(\.id) == [multi.id])
    try workspace.correctLinks(turnID: unrelated.id, issueIDs: [200])
    #expect(workspace.visibleTurns(issueID: 200).count == 2)
    #expect(workspace.discussionIssueID == 100)
    #expect(workspace.issues[0].replySource != nil)
    #expect(throws: IssueTalkError.self) {
      try workspace.correctLinks(turnID: multi.id, issueIDs: [999])
    }
    workspace.issues[0].monitoring = false
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    #expect(restored.turns.count == 2)
    #expect(restored.issues[0].colorIndex == workspace.issues[0].colorIndex)
  }

  @Test func inferenceContextQuotesOnlySelectedSourcesWithinItsBudget() throws {
    var workspace = Workspace()
    workspace.issues = [try item(), try item(id: 200, number: 2, body: "Unrelated cached content")]
    workspace.discussionIssueID = 100
    let source = try comment(id: 10)
    workspace.issues[0].comments = [source]
    workspace.issues[0].replySource = source.htmlURL
    try workspace.appendTurn(
      ConversationTurn(role: .user, body: "Latest local discussion", issueIDs: [100]))
    let context = workspace.inferenceContext(maxCharacters: 1_000)
    #expect(context.contains("Original"))
    #expect(context.contains(source.htmlURL.absoluteString))
    #expect(context.contains("Synthetic update"))
    #expect(context.contains("Latest local discussion"))
    #expect(!context.contains("Unrelated cached content"))
    #expect(context.count <= 1_000)
    #expect(workspace.inferenceContext(maxCharacters: 0).isEmpty)
    try workspace.appendTurn(
      ConversationTurn(role: .user, body: String(repeating: "latest", count: 1_000)))
    #expect(workspace.context(maxCharacters: 100).hasPrefix("user: latest"))
    #expect(workspace.context(maxCharacters: 100).count <= 100)
  }

  @Test func contextIsBoundedWithoutDeletingHistory() throws {
    var workspace = Workspace()
    workspace.contextSummary = "Earlier discussion"
    for index in 0..<20 {
      try workspace.appendTurn(ConversationTurn(role: .user, body: "Note \(index)"))
    }
    #expect(workspace.context(maxCharacters: 100).count <= 100)
    #expect(workspace.context(maxCharacters: 100).contains("Note 19"))
    #expect(workspace.context(maxCharacters: 0).isEmpty)
    #expect(workspace.turns.count == 20)
  }
}
