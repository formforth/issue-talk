import Foundation
import IssueTalkCore

struct WorkspaceStore {
  let url: URL

  init() throws {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ).appendingPathComponent("IssueTalk", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    url = directory.appendingPathComponent("workspace.json")
  }

  func load() throws -> Workspace {
    guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
    return try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
  }

  func save(_ workspace: Workspace) throws {
    let data = try JSONEncoder().encode(workspace)
    try data.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
