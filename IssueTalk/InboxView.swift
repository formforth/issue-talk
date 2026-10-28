import IssueTalkCore
import SwiftUI

struct InboxView: View {
  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Your issue inbox",
        systemImage: "bubble.left.and.bubble.right",
        description: Text("Issues you register will appear here. GitHub connection is coming soon.")
      )
      .navigationTitle("Issue Talk")
      .toolbar {
        NavigationLink {
          List {
            Section("About") {
              Text("A hands-free GitHub Issue inbox")
              Text("GitHub login and issue registration are not available in this initial build.")
            }
          }
          .navigationTitle("Settings")
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }
  }
}
