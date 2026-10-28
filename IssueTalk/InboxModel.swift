import Foundation
import IssueTalkCore
import Observation

@MainActor @Observable
final class InboxModel {
  private(set) var workspace = Workspace()
  private(set) var authenticated = false
  private(set) var busy = false
  var message: String?
  private var storageFailed = false
  private let store: WorkspaceStore?
  private let account = GitHubSession()
  private let browser = OAuthBrowser()
  @ObservationIgnored private lazy var client = GitHubClient(token: { [account] in
    try await account.token()
  })

  init() {
    do {
      let store = try WorkspaceStore()
      let loaded = try store.load()
      self.store = store
      workspace = loaded
    } catch {
      store = nil
      storageFailed = true
      message = "Local data could not be opened. Do not send until storage is available."
    }
  }

  func restoreSession() async {
    authenticated = (try? await account.credentials.load()) != nil
  }

  func signIn() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      try await browser.signIn(using: account)
      authenticated = true
      message = "Connected to GitHub."
    } catch OAuthError.invalidConfiguration {
      message =
        "Configure your OAuth client and HTTPS token broker first. See CONTRIBUTING.md and docs/OAUTH.md."
    } catch { message = "Sign-in did not complete. You can try again." }
  }

  func logout() async {
    guard !busy else { return }
    do {
      try await account.logout()
      authenticated = false
      message = "Signed out. Local Issue history and drafts remain on this device."
    } catch { message = "Could not remove the credential from Keychain. Try again." }
  }

  func register(_ value: String) async -> Int64? {
    guard !busy, authenticated else { return nil }
    busy = true
    defer { busy = false }
    do {
      guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw IssueTalkError.invalidIssueURL
      }
      let identity = try IssueIdentity(url: url)
      async let metadata = client.issue(identity)
      async let comments = client.comments(identity)
      let item = try await MonitoredIssue(
        identity: identity, metadata: metadata, comments: comments)
      guard !workspace.issues.contains(where: { $0.id == item.id || $0.identity == identity })
      else {
        message = "This Issue is already registered."
        return nil
      }
      var updated = workspace
      updated.issues.append(item)
      try commit(updated)
      return item.id
    } catch {
      await reportRequestError(error)
      return nil
    }
  }

  func refresh(_ id: Int64) async {
    guard !busy, authenticated, let item = workspace.issues.first(where: { $0.id == id }) else {
      return
    }
    busy = true
    defer { busy = false }
    do {
      async let metadata = client.issue(item.identity)
      async let comments = client.comments(item.identity)
      let result = try await (metadata, comments)
      try update(id) {
        $0.metadata = result.0
        $0.comments = result.1
      }
    } catch { await reportRequestError(error) }
  }

  func edit(_ id: Int64, draft: String) {
    do { try update(id) { $0.draft = draft } } catch { report(error) }
  }

  func selectReply(_ id: Int64, source: URL?) {
    do {
      try update(id) { item in
        guard source == nil || item.comments.contains(where: { $0.htmlURL == source }) else {
          throw IssueTalkError.invalidResponse
        }
        item.replySource = source
      }
    } catch { report(error) }
  }

  func send(_ id: Int64) async {
    guard !busy, authenticated, let item = workspace.issues.first(where: { $0.id == id }),
      !item.writeUnresolved
    else { return }
    busy = true
    defer { busy = false }
    do {
      let body = try item.commentBody()
      let operation = item.operationID ?? UUID()
      try update(id) {
        $0.operationID = operation
        $0.writeUnresolved = true
      }
      let comment = try await client.post(body, to: item.identity, operationID: operation)
      try update(id) {
        $0.comments.removeAll(where: { $0.id == comment.id })
        $0.comments.append(comment)
        $0.draft = ""
        $0.replySource = comment.htmlURL
        $0.postedCommentURL = comment.htmlURL
        $0.operationID = nil
        $0.writeUnresolved = false
      }
      message = "Comment posted to GitHub."
    } catch {
      if Self.rejectedWrite(error) {
        try? update(id) {
          $0.writeUnresolved = false
          $0.operationID = nil
        }
      }
      await reportRequestError(error)
    }
  }

  func discardUnresolvedDraft(_ id: Int64) {
    do {
      try update(id) {
        $0.draft = ""
        $0.operationID = nil
        $0.writeUnresolved = false
      }
    } catch { report(error) }
  }

  private static func rejectedWrite(_ error: Error) -> Bool {
    guard let error = error as? IssueTalkError else { return false }
    switch error {
    case .authenticationRequired, .permissionDenied, .notFound, .rateLimited: return true
    case .server(let status): return (400...499).contains(status)
    default: return false
    }
  }

  private func update(_ id: Int64, change: (inout MonitoredIssue) throws -> Void) throws {
    var candidate = workspace
    guard let index = candidate.issues.firstIndex(where: { $0.id == id }) else {
      throw IssueTalkError.notFound
    }
    try change(&candidate.issues[index])
    try commit(candidate)
  }

  private func commit(_ candidate: Workspace) throws {
    guard !storageFailed, let store else { throw CocoaError(.fileWriteNoPermission) }
    try store.save(candidate)
    workspace = candidate
  }

  private func reportRequestError(_ error: Error) async {
    if let value = error as? IssueTalkError, value == .authenticationRequired {
      try? await account.logout()
    }
    report(error)
  }

  private func report(_ error: Error) {
    switch error {
    case IssueTalkError.authenticationRequired:
      authenticated = false
      message = "Sign in to GitHub again."
    case IssueTalkError.permissionDenied:
      message = "GitHub denied access. Check repository permissions and organization authorization."
    case IssueTalkError.rateLimited:
      message = "GitHub's rate limit was reached. Wait before refreshing."
    case IssueTalkError.notFound: message = "This Issue is unavailable or you do not have access."
    case IssueTalkError.invalidIssueURL: message = "Paste an HTTPS github.com Issue URL."
    case IssueTalkError.uncertainWrite:
      message =
        """
        Delivery is unknown. Check the Issue on GitHub before discarding this draft.
        It will not be resent automatically.
        """
    default:
      message =
        "The operation could not complete. Your saved draft is retained; check storage, connection, and GitHub."
    }
  }
}
