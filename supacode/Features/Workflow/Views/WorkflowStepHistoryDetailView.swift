import ComposableArchitecture
import ProwlCLIShared
import SwiftUI

struct WorkflowStepHistoryDetailView: View {
  let record: WorkflowRunRecord
  let directory: URL?
  let livePaneIDs: Set<UUID>
  let liveRun: WorkflowRun?
  let onIntent: (WorkflowRunPanelIntent) -> Void
  let onOutput: (WorkflowHistoryOutputIntent) -> Void
  var onInteraction: () -> Void = {}
  @State private var pendingControl: WorkflowAttentionControl?
  @State private var confirmsControl = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(record.run.workflowName).font(.headline)
        Text(WorkflowHistoryStatus.label(record.run.status.state))
          .font(.subheadline).foregroundStyle(.secondary)
        Text(record.run.startedAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption).foregroundStyle(.secondary)
        if let finished = record.run.finishedAt {
          Text(
            "Finished \(finished.formatted(date: .omitted, time: .shortened)) · "
              + "\(Int(max(0, finished.timeIntervalSince(record.run.startedAt))))s"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      ScrollView(.horizontal) {
        HStack {
          ForEach(record.bindings.keys.sorted(), id: \.self) { role in
            let pane = record.bindings[role]?.pane
            Button(role) {
              onInteraction()
              if let pane { onIntent(.focusPane(worktreeID: record.worktree.id, surfaceID: pane.surfaceID)) }
            }
            .disabled(pane.map { !livePaneIDs.contains($0.surfaceID) } ?? true)
            .help(pane.map { "Focus \(role) in \($0.handle)" } ?? "This role has no pane")
          }
        }.controlSize(.small)
      }.scrollIndicators(.never)
      if record.historyIsPartial == true {
        Text("Some control history was omitted after 10,000 records. Recorded outputs remain available.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(WorkflowHistoryStepGroup.groups(record)) { group in
            WorkflowHistoryStepRow(group: group, directory: directory, onOutput: onOutput, onInteraction: onInteraction)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let run = liveRun, run.status.attention != nil {
        attentionControls(run)
      }
      Divider()
      footer
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .confirmationDialog("Confirm Workflow Action", isPresented: $confirmsControl, presenting: pendingControl) {
      control in
      if let run = liveRun, let intent = control.intent(runID: run.id, worktreeID: run.context.worktree.id) {
        Button(control.label, role: control.isDestructive ? .destructive : nil) { onIntent(intent) }
      }
    } message: { control in
      Text(control.confirmationMessage ?? control.label)
    }
  }

  private func attentionControls(_ run: WorkflowRun) -> some View {
    let presentation = WorkflowRunPresentation(run: run, now: Date())
    return VStack(alignment: .leading, spacing: 8) {
      if let attention = run.status.attention {
        Text(attention.message).font(.callout).foregroundStyle(.orange).lineLimit(4)
      }
      ViewThatFits {
        controls(presentation, run: run)
        ScrollView(.horizontal) { controls(presentation, run: run) }
      }
    }
  }

  private func controls(_ presentation: WorkflowRunPresentation, run: WorkflowRun) -> some View {
    HStack {
      ForEach(presentation.attentionControls) { control in
        if control.action == .acceptWithVerdict {
          Menu(control.label) {
            ForEach(control.verdicts, id: \.self) { verdict in
              Button(verdict) {
                if let intent = control.intent(runID: run.id, worktreeID: run.context.worktree.id, verdict: verdict) {
                  onIntent(intent)
                }
              }
            }
          }.help(control.label)
        } else {
          Button(control.label) {
            if control.confirmationMessage != nil {
              pendingControl = control
              confirmsControl = true
            } else if let intent = control.intent(runID: run.id, worktreeID: run.context.worktree.id) {
              onIntent(intent)
            }
          }
          .disabled(control.intent(runID: run.id, worktreeID: run.context.worktree.id) == nil)
          .help(control.label)
        }
      }
    }.controlSize(.small)
  }

  private var footer: some View {
    HStack {
      if let directory {
        Button("Run Folder", systemImage: "folder") { onIntent(.revealRunFolder(directory)) }
          .help("Reveal this run in Finder")
        Button("Log", systemImage: "doc.text") { onOutput(.openFile(directory.appending(path: "log.md"))) }
          .help("Open the recorded workflow log")
        Spacer()
        Menu {
          Button("Keep Run") { onOutput(.keep(directory)) }.help("Protect this run from cleanup")
          Button("Export…") { onOutput(.export(directory)) }
            .disabled(!record.run.status.isTerminal).help("Export this finished run as a ZIP")
          if let run = liveRun, !run.status.isTerminal {
            Button("Cancel Run", role: .destructive) {
              pendingControl = WorkflowAttentionControl(
                action: .cancel, run: run,
                attention: WorkflowAttention(
                  reason: .blocked, stepID: "", role: nil, ordinal: nil,
                  actions: [.cancel], message: ""), skipConsequence: .noDelivery)
              confirmsControl = true
            }
          }
        } label: {
          Image(systemName: "ellipsis").accessibilityLabel("More run actions")
        }
        .help("More run actions")
      }
    }.controlSize(.small)
  }
}

private struct WorkflowHistoryStepRow: View {
  let group: WorkflowHistoryStepGroup
  let directory: URL?
  let onOutput: (WorkflowHistoryOutputIntent) -> Void
  let onInteraction: () -> Void
  @State private var expanded: Bool

  init(
    group: WorkflowHistoryStepGroup, directory: URL?, onOutput: @escaping (WorkflowHistoryOutputIntent) -> Void,
    onInteraction: @escaping () -> Void
  ) {
    self.onInteraction = onInteraction
    self.group = group
    self.directory = directory
    self.onOutput = onOutput
    _expanded = State(initialValue: group.state == "failed" || group.state == "needs_attention")
  }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 10) {
        if group.attempts.isEmpty {
          Text("No execution recorded.").foregroundStyle(.secondary)
        }
        ForEach(Array(group.attempts.enumerated()), id: \.offset) { index, attempt in
          if group.attempts.count > 1 {
            if index == group.attempts.count - 1 {
              Text("Attempt \(index + 1) · \(WorkflowHistoryStatus.label(attempt.state.rawValue))")
                .font(.caption).foregroundStyle(.secondary)
              attemptContent(attempt)
            } else {
              DisclosureGroup("Attempt \(index + 1) · \(WorkflowHistoryStatus.label(attempt.state.rawValue))") {
                attemptContent(attempt)
              }
            }
          } else {
            attemptContent(attempt)
          }
        }
      }
      .font(.callout)
      .padding(.top, 6)
    } label: {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: WorkflowHistoryStatus.symbol(group.state))
          .foregroundStyle(group.state == "failed" || group.state == "needs_attention" ? .orange : .secondary)
        VStack(alignment: .leading, spacing: 3) {
          Text(group.title).font(.subheadline)
          Text(group.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .contentShape(.rect)
    }
    .accessibilityLabel("\(group.title), \(group.subtitle)")
    .onChange(of: expanded) { _, _ in onInteraction() }
  }

  @ViewBuilder
  private func attemptContent(_ attempt: WorkflowRunRecord.Step) -> some View {
    if let error = attempt.error {
      Text(String(error.prefix(1000))).foregroundStyle(.orange).textSelection(.enabled).lineLimit(6)
      Button("Open Full Error") { onOutput(.openText(error, "error.txt")) }
        .help("Open the full recorded error in an external application")
    }
    if let delivery = attempt.delivery, let directory {
      WorkflowHistoryDeliveryView(delivery: delivery, directory: directory, onOutput: onOutput)
    }
    if let outputs = attempt.outputs, !outputs.isEmpty {
      Text(WorkflowHistoryOutputPreview.json(outputs)).font(.caption.monospaced())
        .textSelection(.enabled).lineLimit(8).frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Button("Open Full Output") { onOutput(.openJSON(outputs)) }
          .help("Open the full JSON output in an external application")
        Button("Copy Full Output") { onOutput(.copyJSON(outputs)) }
          .help("Copy the complete JSON output")
      }.controlSize(.small)
      if case .string(let path) = outputs["output_path"] {
        Button("Open Output File", systemImage: "doc") { onOutput(.openFile(URL(filePath: path))) }
          .help("Open the action's recorded output file")
      }
    }
    if attempt.delivery == nil && attempt.outputs == nil && attempt.error == nil {
      Text("No output.").foregroundStyle(.secondary)
    }
    DisclosureGroup("Execution Details") {
      Text("Step: \(attempt.id)").textSelection(.enabled)
      if let ordinal = attempt.ordinal { Text("Invocation: \(ordinal)") }
      if let iteration = attempt.iteration { Text("Round: \(iteration)") }
    }.font(.caption).foregroundStyle(.secondary)
  }
}

private struct WorkflowHistoryDeliveryView: View {
  let delivery: WorkflowDeliveryRecord
  let directory: URL
  let onOutput: (WorkflowHistoryOutputIntent) -> Void
  @State private var preview = "Loading output…"
  @State private var available = false

  private var url: URL {
    WorkflowRunPaths.deliveryURL(runDirectory: directory, name: delivery.name, ordinal: delivery.ordinal)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(delivery.name).font(.subheadline)
      if let verdict = delivery.verdict { Text("Verdict: \(verdict)").font(.caption) }
      Text(preview).textSelection(.enabled).lineLimit(8)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Button("Open Full Output") { onOutput(.openFile(url)) }
          .help("Open the complete delivery in an external application")
        Button("Copy Full Output") { onOutput(.copyFile(url)) }.help("Copy the complete delivery")
        Button("Reveal", systemImage: "folder") { onOutput(.reveal(url)) }.help("Reveal this delivery in Finder")
      }.controlSize(.small).disabled(!available)
    }
    .task(id: url) {
      guard WorkflowSchema.isSlug(delivery.name), delivery.ordinal > 0 else {
        preview = "Output reference is invalid."
        return
      }
      let storage = WorkflowHistoryStorage.configured
      let outputURL = url
      let result = await Task.detached(priority: .utility) {
        try? storage.readChunk(outputURL, offset: 0)
      }.value
      available = result != nil
      preview =
        result.map { String(bytes: $0.data.prefix(4096), encoding: .utf8) ?? "Output preview is not valid UTF-8." }
        ?? "Output is no longer available."
    }
  }
}
