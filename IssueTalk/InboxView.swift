import SwiftUI

struct InboxView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = InboxModel()
  @State private var issueURL = ""
  @State private var path: [Int64] = []

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if !model.authenticated {
          Section {
            Text("Connect GitHub to register Issues and post replies.")
            Button("Connect GitHub") { Task { await model.signIn() } }.disabled(model.busy)
          }
        }
        Section {
          NavigationLink("Conversation · \(model.workspace.unread.count) unread Issues") {
            ConversationView(model: model)
          }
          Text(model.pollStatus).font(.caption).foregroundStyle(.secondary)
        }
        Section("Register an Issue") {
          TextField("https://github.com/owner/repo/issues/1", text: $issueURL)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
          Button("Register Issue") {
            Task {
              if let id = await model.register(issueURL) {
                issueURL = ""
                path.append(id)
              }
            }
          }.disabled(model.busy || !model.authenticated || issueURL.isEmpty)
        }
        Section("Issues") {
          ForEach(model.workspace.issues) { item in
            NavigationLink(value: item.id) {
              VStack(alignment: .leading) {
                Text(item.metadata.title).foregroundStyle(ConversationView.color(item))
                if !item.monitoring { Text("Monitoring stopped — history retained").font(.caption) }
                if item.isUnread && item.monitoring { Text("Unread").font(.caption).bold() }
                Text("\(item.identity.owner)/\(item.identity.repository) #\(item.identity.number)")
                  .font(.caption).foregroundStyle(.secondary)
                if item.writeUnresolved { Text("Check pending delivery on GitHub").font(.caption) }
              }
            }
            .swipeActions {
              Button(item.monitoring ? "Stop monitoring" : "Monitor") {
                model.setMonitoring(item.id, enabled: !item.monitoring)
              }.tint(item.monitoring ? .orange : .blue)
            }
          }
        }
      }
      .refreshable { await model.pollIfNeeded(force: true) }
      .navigationTitle("Issue Talk")
      .navigationDestination(for: Int64.self) { id in IssueDetailView(model: model, id: id) }
      .toolbar { NavigationLink("Settings") { SettingsView(model: model) } }
      .task { await model.restoreSession() }
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
          await model.pollIfNeeded()
          do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
      }
      .alert(
        "Issue Talk",
        isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
      ) {
        Button("OK") { model.message = nil }
      } message: {
        Text(model.message ?? "")
      }
    }
  }
}
