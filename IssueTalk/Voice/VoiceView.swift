import AVFoundation
import Combine
import SwiftUI

struct VoiceView: View {
  @Environment(\.scenePhase) private var scenePhase
  let model: InboxModel
  @State private var voice = VoiceConversation()
  @State private var text = ""

  var body: some View {
    List {
      if let id = model.workspace.discussionIssueID,
        let item = model.workspace.issues.first(where: { $0.id == id })
      {
        Section("Discussion") {
          Text("\(item.identity.owner)/\(item.identity.repository) #\(item.identity.number)")
          NavigationLink("Review draft and reply source") { IssueDetailView(model: model, id: id) }
        }
      }
      Section("Conversation") {
        Text(voice.status).textSelection(.enabled)
        if voice.recognizer.active {
          Label("Listening on this device", systemImage: "mic.fill")
          Text(voice.recognizer.transcript)
        }
        if let error = voice.recognizer.errorMessage { Text(error).foregroundStyle(.secondary) }
        Button(
          (voice.running || voice.busy || voice.speaker.active)
            ? "Stop conversation" : "Start listening"
        ) {
          if voice.running || voice.busy || voice.speaker.active {
            voice.stop()
          } else {
            Task { await voice.start(model) }
          }
        }
        if voice.suggestion != nil {
          Button("Accept suggestion") { voice.acceptSuggestion(model) }
        }
      }
      Section("Text input") {
        TextField("Message or command", text: $text, axis: .vertical)
        Button("Submit") {
          voice.submit(text, model: model)
          text = ""
        }
        .disabled(voice.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Section("Commands") {
        Text("read next · post draft · confirm post · accept suggestion · cancel · stop")
        Text("次を読む · 下書きを投稿 · 投稿を確定 · 提案を採用 · キャンセル · 止めて")
        Text(
          "Posting requires a saved draft, a spoken destination review and a second confirmation.")
        Text("\(model.workspace.unread.count) unread Issues")
      }
    }
    .navigationTitle("Voice conversation")
    .onDisappear { voice.stop() }
    .onChange(of: scenePhase) { _, phase in
      // Background continuation is not enabled until the device feasibility checks pass.
      if phase != .active { voice.stop() }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        .receive(on: RunLoop.main)
    ) { _ in voice.stop() }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
        .receive(on: RunLoop.main)
    ) { notification in
      if ReadingSpeaker.isExternalRouteChange(notification) { voice.stop() }
    }
  }
}
