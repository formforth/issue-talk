import AVFoundation
import Combine
import IssueTalkCore
import Observation

@MainActor @Observable
final class ReadingSpeaker: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var completion: (() -> Void)?
  private var utterance: AVSpeechUtterance?
  private(set) var active = false

  static func isExternalRouteChange(_ notification: Notification) -> Bool {
    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?
      .uintValue
    // Our own playback/recording category transition is not a device interruption.
    return reason != AVAudioSession.RouteChangeReason.categoryChange.rawValue
  }

  func start(_ session: ReadingSession, finished: @escaping () -> Void) throws {
    stop()
    let audio = AVAudioSession.sharedInstance()
    try audio.setCategory(.playback, mode: .spokenAudio)
    try audio.setActive(true)
    let utterance = AVSpeechUtterance(string: session.text)
    self.utterance = utterance
    completion = finished
    active = true
    synthesizer.delegate = self
    synthesizer.speak(utterance)
  }

  func stop() {
    completion = nil
    utterance = nil
    active = false
    synthesizer.stopSpeaking(at: .immediate)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    // AVSpeech delegate callbacks arrive on the main thread, but the protocol is nonisolated.
    let identifier = ObjectIdentifier(utterance)
    MainActor.assumeIsolated {
      guard self.utterance.map(ObjectIdentifier.init) == identifier else { return }
      let finished = completion
      stop()
      finished?()
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    let identifier = ObjectIdentifier(utterance)
    MainActor.assumeIsolated {
      if self.utterance.map(ObjectIdentifier.init) == identifier { stop() }
    }
  }
}
