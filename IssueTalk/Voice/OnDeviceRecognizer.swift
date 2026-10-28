@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

/// SFSpeechAudioBufferRecognitionRequest supports appending from the audio tap queue.
private struct AudioSink: @unchecked Sendable {
  let request: SFSpeechAudioBufferRecognitionRequest
  func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
}

@MainActor @Observable
final class OnDeviceRecognizer {
  private let engine = AVAudioEngine()
  private var task: SFSpeechRecognitionTask?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var timeout: Task<Void, Never>?
  private var generation = UUID()
  private var tapInstalled = false
  private(set) var active = false
  private(set) var transcript = ""
  var errorMessage: String?

  func start(finished: @escaping @MainActor (String) -> Void) async {
    stop()
    errorMessage = nil
    let requestedGeneration = generation
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard status == .authorized, await AVAudioApplication.requestRecordPermission() else {
      errorMessage = "Enable speech recognition and microphone access in Settings."
      return
    }
    guard generation == requestedGeneration else { return }
    guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
      recognizer.supportsOnDeviceRecognition
    else {
      errorMessage =
        "On-device recognition is unavailable for this device or language. Use text input."
      return
    }
    do {
      let request = try configureAudio()
      recognize(using: recognizer, request: request, finished: finished)
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
        self?.stop()
        self?.errorMessage = "Listening timed out. Start again or use text input."
      }
    } catch {
      stop()
      errorMessage = "Microphone could not start. Check the audio route or use text input."
    }
  }

  private func configureAudio() throws -> SFSpeechAudioBufferRecognitionRequest {
    let audio = AVAudioSession.sharedInstance()
    try audio.setCategory(
      .playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
    try audio.setActive(true)
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.request = request
    let sink = AudioSink(request: request)
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw CocoaError(.fileReadUnknown)
    }
    node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer)
    }
    tapInstalled = true
    engine.prepare()
    try engine.start()
    active = true
    transcript = ""
    return request
  }

  private func recognize(
    using recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    finished: @escaping @MainActor (String) -> Void
  ) {
    let token = generation
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal == true
      let failed = error != nil
      Task { @MainActor [weak self] in
        guard let self, generation == token else { return }
        if let text { transcript = text }
        if final, let text {
          stop()
          finished(text)
        } else if failed {
          stop()
          errorMessage = "Recognition stopped. No partial transcript was executed."
        }
      }
    }
  }

  func stop() {
    generation = UUID()
    timeout?.cancel()
    timeout = nil
    engine.stop()
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    active = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
