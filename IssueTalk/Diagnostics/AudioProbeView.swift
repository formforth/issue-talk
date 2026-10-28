#if DEBUG
  import AVFoundation
  import SwiftUI

  struct AudioProbeView: View {
    @State private var probe = AudioProbe()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
      List {
        Section("Physical iPhone audio probe") {
          Text(
            "Use synthetic speech only. Recordings stay in this app's temporary storage. Clear them when finished."
          )
          Button("Record for up to 60 seconds") { Task { await probe.start() } }
            .disabled(probe.recording)
          Button("Stop") {
            probe.stop()
            probe.log("Stopped by user.")
          }
          Button("Play last recording") { probe.play() }
          Button("Speak lock-screen test sentence") { probe.speak() }
          Button("Clear recording and events", role: .destructive) { probe.clear() }
        }
        Section("Events (not uploaded)") {
          ForEach(Array(probe.events.enumerated()), id: \.offset) { _, event in Text(event) }
        }
      }
      .navigationTitle("Audio feasibility")
      .onChange(of: scenePhase) { _, phase in probe.log("Scene: \(String(describing: phase))") }
      .onReceive(
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).receive(
          on: RunLoop.main)
      ) { _ in
        probe.stop()
        probe.log("Audio interruption; session stopped. Restart explicitly.")
      }
      .onReceive(
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(
          on: RunLoop.main)
      ) { _ in
        probe.log("Audio route changed.")
      }
      .onDisappear { probe.clear() }
    }
  }
#endif
