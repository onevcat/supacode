import ProwlCLIShared
import SwiftUI

struct WorkflowHistoryJSONView: View {
  let values: [String: WorkflowJSONValue]
  let worktree: URL
  let onOutput: (WorkflowHistoryOutputIntent) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Output").font(.caption).foregroundStyle(.secondary)
        Spacer()
        WorkflowHistoryIconButton(label: "Open full JSON output", symbol: "arrow.up.forward.square") {
          onOutput(.openJSON(values))
        }
        WorkflowHistoryIconButton(label: "Copy full JSON output", symbol: "doc.on.doc") {
          onOutput(.copyJSON(values))
        }
      }
      ForEach(WorkflowHistoryOutputField.fields(values)) { field in
        WorkflowHistoryOutputFieldView(field: field, worktree: worktree, onOutput: onOutput)
      }
      if values.count > 32 { Text("\(values.count - 32) more fields in full output").foregroundStyle(.secondary) }
    }
    .font(.caption)
  }
}

private struct WorkflowHistoryOutputFieldView: View {
  let field: WorkflowHistoryOutputField
  let worktree: URL
  let onOutput: (WorkflowHistoryOutputIntent) -> Void
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        if let children = field.children, !children.isEmpty {
          Button {
            expanded.toggle()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption2).frame(width: 10).accessibilityHidden(true)
              valueRow
            }.contentShape(.rect)
          }
          .buttonStyle(.plain)
          .help("\(expanded ? "Collapse" : "Expand") \(field.key)")
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        } else {
          Color.clear.frame(width: 10, height: 1)
          valueRow
        }
        if let url = field.fileURL {
          WorkflowHistoryIconButton(label: "Open \(url.lastPathComponent)", symbol: "arrow.up.forward.square") {
            onOutput(.openArtifact(url, worktree: worktree))
          }
          WorkflowHistoryIconButton(label: "Reveal \(url.lastPathComponent) in Finder", symbol: "folder") {
            onOutput(.revealArtifact(url, worktree: worktree))
          }
        }
        if case .string(let value) = field.value {
          WorkflowHistoryIconButton(label: "Copy \(field.key)", symbol: "doc.on.doc") { onOutput(.copyText(value)) }
        }
      }
      if expanded, let children = field.children {
        ForEach(children) { child in
          WorkflowHistoryOutputFieldView(field: child, worktree: worktree, onOutput: onOutput)
        }
        .padding(.leading, 14)
        if field.childCount > children.count {
          Text("\(field.childCount - children.count) more fields in full output")
            .foregroundStyle(.secondary).padding(.leading, 30)
        }
      }
    }
  }

  private var valueRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(field.displayKey)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)
        .help(
          field.key == "output_path"
            ? "The saved JSON result file; output contains its fields" : String(field.key.prefix(300)))
      Text(field.fileURL?.path ?? field.summary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption.monospaced())
    .lineLimit(1)
    .truncationMode(.middle)
  }
}

struct WorkflowHistoryDeliveryView: View {
  let delivery: WorkflowDeliveryRecord
  let directory: URL
  let onOutput: (WorkflowHistoryOutputIntent) -> Void
  @State private var preview: WorkflowHistoryTextPreview?
  @State private var error: String?

  private var url: URL {
    if delivery.path.hasPrefix("/") { return URL(filePath: delivery.path) }
    return directory.appending(path: delivery.path)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(delivery.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        if let verdict = delivery.verdict { Text(verdict).font(.caption.weight(.medium)).lineLimit(1) }
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          WorkflowHistoryIconButton(label: "Open full output", symbol: "arrow.up.forward.square") {
            onOutput(.openFile(url))
          }
          WorkflowHistoryIconButton(label: "Copy full output", symbol: "doc.on.doc") { onOutput(.copyFile(url)) }
          WorkflowHistoryIconButton(label: "Reveal output in Finder", symbol: "folder") { onOutput(.reveal(url)) }
        }.disabled(preview == nil)
      }
      if let preview {
        Text(preview.text.isEmpty ? "No output" : preview.text)
          .lineLimit(6)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        if preview.remainingCharacters > 0 {
          Text("\(preview.remainingCharacters.formatted()) more characters…")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Text(error ?? "Loading output…").foregroundStyle(.secondary)
      }
    }
    .task(id: url) {
      preview = nil
      error = nil
      guard WorkflowSchema.isSlug(delivery.name), delivery.ordinal > 0 else {
        error = "Output reference is invalid."
        return
      }
      let storage = WorkflowHistoryStorage.configured
      let outputURL = url
      let result = await Task.detached(priority: .utility) { () -> WorkflowHistoryTextPreview? in
        guard let data = try? storage.read(outputURL, limit: WorkflowSizeLimits.payload),
          let text = String(data: data, encoding: .utf8)
        else { return nil }
        return WorkflowHistoryTextPreview(text)
      }.value
      guard !Task.isCancelled else { return }
      preview = result
      if result == nil { error = "Saved output could not be read." }
    }
  }
}
