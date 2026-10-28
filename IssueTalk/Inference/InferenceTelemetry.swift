import Foundation

/// Opt-in metadata only. Never records prompts, transcripts, Issue IDs/URLs, drafts or responses.
@MainActor
struct InferenceTelemetry {
  struct Entry: Codable {
    let date: Date
    let promptVersion: String
    let backend: String
    let osVersion: String
    let durationMilliseconds: Int
    let intent: String?
    let succeeded: Bool
  }

  static var enabled: Bool {
    get { UserDefaults.standard.bool(forKey: "inferenceTelemetryEnabled") }
    set { UserDefaults.standard.set(newValue, forKey: "inferenceTelemetryEnabled") }
  }

  static func record(started: ContinuousClock.Instant, intent: String?, succeeded: Bool) {
    guard enabled else { return }
    do {
      let url = try fileURL()
      let previous = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))) ?? []
      let duration = started.duration(to: .now).components
      let milliseconds = Int(
        duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
      let entry = Entry(
        date: Date(), promptVersion: LocalPrompt.version,
        backend: "Apple Foundation Models (system-managed)",
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        durationMilliseconds: milliseconds, intent: intent, succeeded: succeeded)
      try JSONEncoder().encode(Array((previous + [entry]).suffix(100))).write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var excluded = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excluded.setResourceValues(values)
    } catch {
      // Diagnostics must never prevent a manual workflow or expose input.
    }
  }

  static func clear() {
    if let url = try? fileURL() { try? FileManager.default.removeItem(at: url) }
  }

  private static func fileURL() throws -> URL {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    return directory.appendingPathComponent("inference-metadata.json")
  }
}
