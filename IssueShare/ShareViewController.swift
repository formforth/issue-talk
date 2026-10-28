import IssueTalkCore
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let addButton = UIButton(type: .system)
  private var identity: IssueIdentity?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.numberOfLines = 0
    status.text = "Checking shared Issue URL…"
    addButton.setTitle("Add Issue", for: .normal)
    addButton.isEnabled = false
    addButton.addTarget(self, action: #selector(addIssue), for: .touchUpInside)
    let cancel = UIButton(type: .system)
    cancel.setTitle("Cancel", for: .normal)
    cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [status, addButton, cancel])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    loadURL()
  }

  private func loadURL() {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let types = [UTType.url.identifier, UTType.plainText.identifier]
    guard
      let type = types.first(where: { type in
        providers.contains { $0.hasItemConformingToTypeIdentifier(type) }
      }), let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) })
    else {
      status.text = "Share an HTTPS github.com Issue URL."
      return
    }
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
      let value = (item as? URL)?.absoluteString ?? (item as? String)
      Task { @MainActor [weak self] in self?.validate(value) }
    }
  }

  private func validate(_ value: String?) {
    guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      let identity = try? IssueIdentity(url: url)
    else {
      status.text = "This is not a supported GitHub Issue URL."
      return
    }
    self.identity = identity
    if SharedIssueQueue() == nil {
      status.text =
        "Sharing needs the App Group setup in CONTRIBUTING.md. Copy this URL and paste it in Issue Talk."
      addButton.setTitle("Copy Issue URL", for: .normal)
    } else {
      status.text =
        "Add \(identity.owner)/\(identity.repository) #\(identity.number)? Open Issue Talk afterward to fetch it."
    }
    addButton.isEnabled = true
  }

  @objc private func addIssue() {
    guard let identity else { return }
    do {
      if let queue = SharedIssueQueue() {
        try queue.enqueue(identity)
      } else {
        UIPasteboard.general.url = identity.url
      }
      close()
    } catch { status.text = "Could not save the shared URL. Try again or copy it manually." }
  }

  @objc private func close() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
