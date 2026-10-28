import IssueTalkCore
import SwiftUI

struct IssueDetailView: View {
  @Bindable var model: InboxModel
  let id: Int64

  private var item: MonitoredIssue? { model.workspace.issues.first(where: { $0.id == id }) }

  var body: some View {
    if let item {
      List {
        Section {
          Text(item.metadata.title).font(.headline)
          MarkdownView(source: item.metadata.body ?? "")
          Link("Open Issue on GitHub", destination: item.identity.url)
          Button("Discuss this Issue") { model.setDiscussionIssue(id) }
        }
        Section("Comments — tap Reply to select the source") {
          ForEach(item.comments) { comment in
            VStack(alignment: .leading, spacing: 8) {
              MarkdownView(source: comment.body)
              HStack {
                Link("GitHub", destination: comment.htmlURL)
                Spacer()
                Button("Reply") { model.selectReply(id, source: comment.htmlURL) }
                  .disabled(item.writeUnresolved || model.busy)
              }.font(.caption)
            }
          }
        }
        Section(
          "Post to \(item.identity.owner)/\(item.identity.repository) #\(item.identity.number)"
        ) {
          if let source = item.replySource {
            Link("Reply source", destination: source)
          } else {
            Text("New topic — no reply source")
          }
          Button("Start a new topic") { model.selectReply(id, source: nil) }
            .disabled(item.writeUnresolved || model.busy)
          TextField(
            "Draft comment",
            text: Binding(get: { self.item?.draft ?? "" }, set: { model.edit(id, draft: $0) }),
            axis: .vertical
          )
          .lineLimit(3...10).disabled(item.writeUnresolved || model.busy)
          if item.writeUnresolved {
            Text(
              "Delivery is unresolved. Check GitHub first. This draft is saved and will not be resent automatically."
            )
            Button("Discard unresolved draft", role: .destructive) {
              model.discardUnresolvedDraft(id)
            }
            .disabled(model.busy)
          } else {
            Button(model.busy ? "Working…" : "Post comment") { Task { await model.send(id) } }
              .disabled(
                model.busy || !model.authenticated
                  || item.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          if let url = item.postedCommentURL { Link("Last posted comment", destination: url) }
        }
      }
      .navigationTitle("Issue #\(item.identity.number)")
      .refreshable { await model.refresh(id) }
      .task { await model.refresh(id) }
    }
  }
}
