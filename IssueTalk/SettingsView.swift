import SwiftUI

struct SettingsView: View {
  @Bindable var model: InboxModel

  var body: some View {
    List {
      Section("GitHub") {
        Text(model.authenticated ? "Connected" : "Not connected")
        if model.authenticated {
          Button("Sign out") { Task { await model.logout() } }.disabled(model.busy)
          Text("Signing out removes the token. Issue history and drafts stay on this device.")
            .font(.caption)
        } else {
          Button("Connect GitHub") { Task { await model.signIn() } }.disabled(model.busy)
          Text("OAuth setup instructions are in CONTRIBUTING.md and docs/OAUTH.md.")
        }
      }
      #if DEBUG
        Section("Diagnostics") {
          NavigationLink("Audio feasibility") { AudioProbeView() }
        }
      #endif
      Section("About") {
        Text("A hands-free GitHub Issue inbox")
        Text(
          "Manual text and read-next commands work without an LLM. Local suggestions require an eligible iPhone, iOS 26 and Apple Intelligence."
        )
      }
    }.navigationTitle("Settings")
  }
}
