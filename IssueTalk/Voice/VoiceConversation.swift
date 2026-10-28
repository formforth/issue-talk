import Foundation
import IssueTalkCore
import Observation

@MainActor @Observable
final class VoiceConversation {
  let recognizer = OnDeviceRecognizer()
  let speaker = ReadingSpeaker()
  private(set) var running = false
  private(set) var busy = false
  private(set) var status = "Start listening, or type a message."
  private(set) var suggestion: RoutingSuggestion?
  private var confirmation: PostConfirmation?
  private let inference = makeLocalInference()
  private var generation = UUID()
  private var inferenceTask: Task<Void, Never>?

  func start(_ model: InboxModel) async {
    running = true
    await listen(model)
  }

  func stop() {
    running = false
    generation = UUID()
    inferenceTask?.cancel()
    inferenceTask = nil
    busy = false
    confirmation = nil
    suggestion = nil
    recognizer.stop()
    speaker.stop()
    status = "Stopped. Interrupted readings remain unread."
  }

  func submit(_ text: String, model: InboxModel) {
    let command = VoiceCommand.parse(text)
    if command == .stop || command == .cancel {
      stop()
      return
    }
    guard !busy else { return }
    recognizer.stop()
    speaker.stop()
    let ids = model.workspace.discussionIssueID.map { Set([$0]) } ?? []
    model.addNote(text, issueIDs: ids)
    switch command {
    case .readNext: readNext(model)
    case .postDraft: requestPost(model)
    case .confirmPost: confirmPost(model)
    case .acceptSuggestion: acceptSuggestion(model)
    default: infer(text, model: model)
    }
  }

  func acceptSuggestion(_ model: InboxModel) {
    guard let suggestion else { return }
    self.suggestion = nil
    confirmation = nil
    do {
      switch suggestion.intent {
      case .readNext: readNext(model)
      case .switchIssue:
        guard let url = URL(string: suggestion.issueURL),
          let identity = try? IssueIdentity(url: url),
          let item = model.workspace.monitored.first(where: { $0.identity == identity })
        else { throw LocalInferenceError.invalidSuggestion }
        model.setDiscussionIssue(item.id)
        say(
          "Discussing \(item.metadata.title).",
          model: model)
      case .draft:
        let proposal = try DraftProposal(suggestion: suggestion, workspace: model.workspace)
        guard model.applyDraft(proposal) else { return }
        model.setDiscussionIssue(proposal.issueID)
        say("Draft saved. Say post draft to review its destination before sending.", model: model)
      case .chat: break
      }
    } catch {
      status = "The suggestion could not be validated. Choose the Issue and reply source manually."
    }
  }

  private func infer(_ text: String, model: InboxModel) {
    confirmation = nil
    suggestion = nil
    busy = true
    status = "Thinking on this device…"
    let token = generation
    let anchors = model.workspace.monitored.map {
      "Issue: \($0.identity.url.absoluteString), selected reply: \($0.replySource?.absoluteString ?? "new topic"). "
        + "Observed comment URLs: "
        + $0.comments.suffix(10).map { $0.htmlURL.absoluteString }.joined(separator: " ")
    }.joined(separator: "\n")
    let context =
      String(anchors.prefix(4_000)) + "\n" + model.workspace.context(maxCharacters: 4_000)
    let urls = model.workspace.monitored.map { $0.identity.url.absoluteString }
    inferenceTask = Task {
      do {
        let result = try await inference.suggest(
          userText: String(text.prefix(4_000)), context: context, issueURLs: urls)
        guard token == generation, !Task.isCancelled else { return }
        busy = false
        guard !result.text.isEmpty || result.intent != .chat else {
          throw LocalInferenceError.invalidSuggestion
        }
        if result.intent == .chat {
          let ids = model.workspace.discussionIssueID.map { Set([$0]) } ?? []
          model.recordAssistant(result.text, issueIDs: ids)
          say(result.text, model: model)
        } else {
          suggestion = result
          say(
            "Suggestion: \(result.intent.rawValue), \(result.issueURL). Say accept suggestion or cancel.",
            model: model)
        }
      } catch {
        guard token == generation else { return }
        busy = false
        status =
          "Local inference is unavailable. Read-next commands and manual text replies still work."
      }
    }
  }

  private func readNext(_ model: InboxModel) {
    confirmation = nil
    suggestion = nil
    guard let reading = model.workspace.nextReading() else {
      say("No unread Issues remain.", model: model)
      return
    }
    do {
      status = reading.text
      try speaker.start(reading) {
        model.completeReading(reading)
        self.say(
          "\(model.workspace.unread.count) unread Issues remain. What would you like to do?",
          model: model)
      }
    } catch { status = "Speech could not start. This Issue remains unread." }
  }

  private func requestPost(_ model: InboxModel) {
    do {
      guard let id = model.workspace.discussionIssueID,
        let item = model.workspace.monitored.first(where: { $0.id == id })
      else { throw LocalInferenceError.invalidSuggestion }
      _ = try PostConfirmation(issue: item)
      confirmation = nil
      let source = item.replySource.map { "Reply source: \($0.absoluteString)." } ?? "New topic."
      say(
        "Post to \(item.identity.owner)/\(item.identity.repository), Issue \(item.identity.number). \(source) "
          + "Draft: \(item.draft). Say confirm post within one minute, or cancel.", model: model
      ) {
        // Start the deadline only after the complete destination/body review was spoken.
        self.confirmation = try? PostConfirmation(issue: item)
      }
    } catch {
      confirmation = nil
      status = "Choose an Issue and save a valid draft first."
    }
  }

  private func confirmPost(_ model: InboxModel) {
    guard let confirmation else {
      status = "Say post draft first to review its destination."
      return
    }
    self.confirmation = nil
    do {
      guard !model.busy else {
        status = "Wait for the current request, then review the draft again."
        return
      }
      let id = try confirmation.validate(in: model.workspace)
      busy = true
      inferenceTask = Task {
        await model.send(id)
        busy = false
        status = model.message ?? "Check the Issue for delivery status."
        model.message = nil
        // Do not resume listening or retry a write after a delivery result.
      }
    } catch {
      status = "Confirmation expired or the draft changed. Review it again before posting."
    }
  }

  private func say(_ text: String, model: InboxModel, finished: @escaping () -> Void = {}) {
    recognizer.stop()
    status = text
    do {
      try speaker.speak(text) {
        finished()
        Task { await self.listen(model) }
      }
    } catch {
      running = false
      status = "Speech is unavailable. Use text input."
    }
  }

  private func listen(_ model: InboxModel) async {
    guard running, !busy, !speaker.active else { return }
    await recognizer.start { [weak self] text in self?.submit(text, model: model) }
  }
}
