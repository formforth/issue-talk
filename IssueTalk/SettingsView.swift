import SwiftUI

struct SettingsView: View {
  @Bindable var model: InboxModel
  @State private var telemetryEnabled = InferenceTelemetry.enabled

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
      Section("Local inference diagnostics") {
        Toggle("Record inference metadata", isOn: $telemetryEnabled)
          .onChange(of: telemetryEnabled) { _, enabled in InferenceTelemetry.enabled = enabled }
        Text(
          """
          Off by default. Keeps at most 100 local timing/outcome records,
          without conversation text or Issue identifiers.
          """
        )
        .font(.caption)
        Button("Delete inference metadata", role: .destructive) { InferenceTelemetry.clear() }
      }
      Section("About") {
        Text("A hands-free GitHub Issue inbox")
        Text(
          """
          Manual text and read-next commands work without an LLM.
          Local suggestions require an eligible iPhone, iOS 26 and Apple Intelligence.
          """
        )
      }
    }.navigationTitle("Settings")
  }
}
