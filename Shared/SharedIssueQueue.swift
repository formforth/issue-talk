import Foundation
import IssueTalkCore

/// Each receipt is an independent atomic file: extension and app never rewrite a shared array.
struct SharedIssueQueue {
  struct Receipt: Codable, Identifiable {
    let id: UUID
    let identity: IssueIdentity
  }

  let directory: URL

  init?() {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "IssueTalkAppGroup") as? String,
      group.hasPrefix("group."), !group.contains("$("),
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    directory = container.appendingPathComponent("PendingIssues", isDirectory: true)
  }

  init(directory: URL) { self.directory = directory }

  func enqueue(_ identity: IssueIdentity) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let receipt = Receipt(id: UUID(), identity: identity)
    try JSONEncoder().encode(receipt).write(
      to: path(receipt.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
  }

  func pending() throws -> [Receipt] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey]
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .prefix(100).map { url in
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_192 else { throw IssueTalkError.invalidIssueURL }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: url))
        guard url.lastPathComponent == path(receipt.id).lastPathComponent else {
          throw IssueTalkError.invalidIssueURL
        }
        return receipt
      }
  }

  func remove(_ receipt: Receipt) throws {
    try FileManager.default.removeItem(at: path(receipt.id))
  }

  private func path(_ id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
  }
}
