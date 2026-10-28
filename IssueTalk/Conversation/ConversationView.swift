import AVFoundation
import Combine
import IssueTalkCore
import SwiftUI

struct ConversationView: View {
  @Bindable var model: InboxModel
  @State private var filter: Int64?
  @State private var note = ""
  @State private var linkedIssues: Set<Int64> = []
  @State private var speaker = ReadingSpeaker()
  @State private var scrollPositions: [String: String] = [:]
  @State private var scrollID: String?
  @State private var editingTurn: ConversationTurn?
  @State private var showSummary = false
  @State private var summary = ""

  private var filterKey: String { filter.map(String.init) ?? "all" }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.horizontal) {
        HStack {
          chip("All (\(model.workspace.unread.count))", id: nil)
          ForEach(model.workspace.issues) { item in
            chip(
              "#\(item.identity.number)\(item.isUnread && item.monitoring ? " •" : "")", id: item.id
            )
          }
        }.padding(8)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(model.workspace.timeline(issueID: filter)) { turn in
            bubble(turn).id(turn.id)
          }
          if model.workspace.timeline(issueID: filter).isEmpty {
            Text("Local conversation notes and completed readings appear here.")
              .foregroundStyle(.secondary).padding()
          }
        }.scrollTargetLayout().padding()
      }
      .scrollPosition(id: $scrollID)
      .onChange(of: filter) { old, _ in
        let key = old.map(String.init) ?? "all"
        if let scrollID { scrollPositions[key] = scrollID }
        scrollID = scrollPositions[filterKey]
      }
      Divider()
      HStack {
        if speaker.active {
          Button("Stop reading") { speaker.stop() }
        } else {
          Button("Read next unread") { readNext() }.disabled(model.workspace.unread.isEmpty)
        }
        Spacer()
        Text("\(model.workspace.unread.count) unread Issues").font(.caption)
      }.padding(.horizontal).padding(.top, 8)
      HStack {
        Menu("Related Issues (\(linkedIssues.count))") {
          ForEach(model.workspace.issues) { item in
            Button("\(linkedIssues.contains(item.id) ? "✓ " : "")\(item.metadata.title)") {
              if !linkedIssues.insert(item.id).inserted { linkedIssues.remove(item.id) }
            }
          }
          Button("Unrelated chat") { linkedIssues.removeAll() }
        }
        Spacer()
        Button("Context summary") {
          summary = model.workspace.contextSummary
          showSummary = true
        }
      }.font(.caption).padding(.horizontal)
      HStack {
        TextField("Local note — posting is in Issue details", text: $note, axis: .vertical)
          .lineLimit(1...5)
        Button("Save") {
          model.addNote(note, issueIDs: linkedIssues)
          note = ""
        }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.padding()
    }
    .navigationTitle("Conversation")
    .sheet(item: $editingTurn) { turn in
      AssociationEditor(model: model, turn: turn)
    }
    .sheet(isPresented: $showSummary) {
      NavigationStack {
        TextEditor(text: $summary).padding()
          .navigationTitle("Context summary")
          .toolbar {
            Button("Save") {
              model.saveContextSummary(summary)
              showSummary = false
            }
          }
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        .receive(on: RunLoop.main)
    ) { _ in speaker.stop() }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
        .receive(on: RunLoop.main)
    ) { notification in
      if ReadingSpeaker.isExternalRouteChange(notification) { speaker.stop() }
    }
    .onDisappear { speaker.stop() }
  }

  private func chip(_ title: String, id: Int64?) -> some View {
    Button(title) { filter = id }
      .buttonStyle(.bordered).tint(filter == id ? .accentColor : .secondary)
  }

  private func bubble(_ turn: TimelineEntry) -> some View {
    HStack {
      if turn.role == .user { Spacer(minLength: 32) }
      VStack(alignment: .leading, spacing: 6) {
        MarkdownView(source: turn.body)
        HStack {
          ForEach(model.workspace.issues.filter { turn.issueIDs.contains($0.id) }) { item in
            Text("#\(item.identity.number)").foregroundStyle(Self.color(item))
          }
          Spacer()
          Text(turn.createdAt, style: .time).foregroundStyle(.secondary)
        }.font(.caption)
      }
      .padding(12)
      .background(
        turn.role == .user ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .contextMenu {
        if let id = turn.localTurnID {
          Button("Correct related Issues") {
            editingTurn = model.workspace.turns.first { $0.id == id }
          }
        }
        if let source = turn.sourceURL { Link("Open source on GitHub", destination: source) }
      }
      if turn.role != .user { Spacer(minLength: 32) }
    }
  }

  static func color(_ item: MonitoredIssue) -> Color {
    [.blue, .purple, .orange, .teal, .pink, .indigo][item.colorIndex]
  }

  private func readNext() {
    guard let session = model.workspace.nextReading() else { return }
    do {
      try speaker.start(session) { model.completeReading(session) }
    } catch { model.message = "Speech could not start. This Issue remains unread." }
  }
}

private struct AssociationEditor: View {
  @Environment(\.dismiss) private var dismiss
  let model: InboxModel
  let turn: ConversationTurn
  @State private var selected: Set<Int64> = []

  var body: some View {
    NavigationStack {
      List(model.workspace.issues) { item in
        Toggle(
          item.metadata.title,
          isOn: Binding(
            get: { selected.contains(item.id) },
            set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }
          ))
      }
      .navigationTitle("Related Issues")
      .toolbar {
        Button("Save") {
          model.correctLinks(turn.id, issueIDs: selected)
          dismiss()
        }
      }
      .onAppear { selected = turn.issueIDs }
    }
  }
}
