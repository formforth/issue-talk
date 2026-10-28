#if DEBUG
  import AVFoundation
  import Observation

  @MainActor @Observable
  final class AudioProbe: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private var recordingURL: URL?
    private(set) var events: [String] = []
    private(set) var recording = false

    func start() async {
      guard await AVAudioApplication.requestRecordPermission() else {
        log("Microphone permission denied; enable it in Settings.")
        return
      }
      do {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
          "issue-talk-audio-probe.m4a")
        let settings: [String: Any] = [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.prepareToRecord() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: url.path)
        guard recorder.record(forDuration: 60) else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
        recordingURL = url
        recording = true
        log(
          "Recording started (60-second maximum). Lock the phone, speak, unlock, then stop and play."
        )
      } catch { log("Audio could not start. Check permissions, route, and device availability.") }
    }

    nonisolated func audioRecorderDidFinishRecording(
      _ recorder: AVAudioRecorder, successfully flag: Bool
    ) {
      Task { @MainActor [weak self] in
        self?.recording = false
        self?.log(flag ? "Recording completed." : "Recording failed.")
      }
    }

    func stop() {
      recorder?.stop()
      recorder = nil
      recording = false
      player?.stop()
      player = nil
      speech.stopSpeaking(at: .immediate)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play() {
      stop()
      guard let recordingURL else { return }
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: recordingURL)
        self.player = player
        player.play()
        log("Playing the local microphone probe.")
      } catch { log("Playback failed.") }
    }

    func speak() {
      stop()
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        speech.speak(
          AVSpeechUtterance(
            string:
              """
              Issue Talk audio probe. Lock the screen and check whether this sentence continues.
              This is a feasibility measurement, not a guarantee of background operation.
              """
          ))
        log("Speech playback started.")
      } catch { log("Speech playback failed.") }
    }

    func log(_ message: String) {
      events.append("\(Date.now.formatted(date: .omitted, time: .standard)) — \(message)")
      if events.count > 50 { events.removeFirst() }
    }

    func clear() {
      stop()
      if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
      recordingURL = nil
      events.removeAll()
    }
  }
#endif
