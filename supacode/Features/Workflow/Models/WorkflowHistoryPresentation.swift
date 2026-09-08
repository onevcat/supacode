import Foundation
import ProwlCLIShared

nonisolated enum WorkflowHistoryScope: String, CaseIterable, Equatable, Sendable {
  case pane = "This Pane"
  case worktree = "This Worktree"
  case all = "All Runs"
}

nonisolated struct WorkflowHistoryContext: Equatable, Sendable {
  var paneID: UUID?
  var session: String?
  var worktreeID: String?
  var livePaneIDs: Set<UUID> = []
}

nonisolated enum WorkflowHistoryStatus {
  static func label(_ state: String) -> String {
    switch state {
    case "completed": "Completed"
    case "active", "running": "Running"
    case "needs_attention": "Needs Attention"
    case "failed": "Failed"
    case "skipped": "Skipped"
    case "branch_not_selected": "Branch not selected"
    case "pending": "Not started"
    case "not_run": "Not run"
    case "cancelled": "Cancelled"
    case "interrupted": "Interrupted"
    case "iteration_limit_reached": "Iteration limit reached"
    default: "Unavailable"
    }
  }

  static func symbol(_ state: String) -> String {
    switch state {
    case "completed": "checkmark.circle.fill"
    case "active", "running": "play.circle"
    case "needs_attention", "failed": "exclamationmark.circle.fill"
    case "skipped", "branch_not_selected": "forward.end.circle"
    case "cancelled", "interrupted": "stop.circle"
    default: "circle"
    }
  }
}

nonisolated struct WorkflowHistoryStepGroup: Identifiable {
  let id: String
  let title: String
  let state: String
  let iteration: Int?
  let attempts: [WorkflowRunRecord.Step]

  var subtitle: String {
    var parts = [WorkflowHistoryStatus.label(state)]
    if let iteration { parts.append("Round \(iteration)") }
    if attempts.count > 1 { parts.append("\(attempts.count) attempts") }
    return parts.joined(separator: " · ")
  }

  static func groups(_ record: WorkflowRunRecord) -> [Self] {
    var definitions = record.stepDefinitions ?? []
    let known = Set(definitions.map(\.id))
    var added: Set<String> = []
    for step in record.steps where !known.contains(step.id) && added.insert(step.id).inserted {
      definitions.append(.init(id: step.id, title: step.title ?? step.id, loop: nil))
    }
    let positions = Dictionary(
      definitions.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    var result: [(group: Self, order: [Int])] = []
    for definition in definitions {
      let records = record.steps.filter { $0.id == definition.id }
      func path(_ step: WorkflowRunRecord.Step) -> [String] {
        step.iterationPath ?? step.iteration.map { ["legacy:\($0)"] } ?? []
      }
      var paths: [[String]] = []
      for step in records where !paths.contains(path(step)) { paths.append(path(step)) }
      if paths.isEmpty { paths = [[]] }
      for path in paths {
        let attempts = records.filter { ($0.iterationPath ?? $0.iteration.map { ["legacy:\($0)"] } ?? []) == path }
        let latest = attempts.last
        var state = latest?.state.rawValue ?? (record.run.status.isTerminal ? "not_run" : "pending")
        if latest?.state == .active && record.run.status.isTerminal { state = "interrupted" }
        if record.run.status.attention?.step == definition.id && latest?.state == .active { state = "needs_attention" }
        if latest?.state == .skipped && latest?.branchExcluded == true { state = "branch_not_selected" }
        let group = Self(
          id: "\(definition.id):\(path.joined(separator: "/"))",
          title: latest?.title ?? definition.title, state: state, iteration: latest?.iteration, attempts: attempts)
        var order: [Int] = []
        for component in path {
          let parts = component.split(separator: ":")
          let loop = parts.first.map(String.init) ?? ""
          order += [positions[loop] ?? positions[definition.loop ?? ""] ?? 0, Int(parts.last ?? "0") ?? 0]
        }
        order.append(positions[definition.id] ?? 0)
        result.append((group, order))
      }
    }
    return result.sorted { $0.order.lexicographicallyPrecedes($1.order) }.map(\.group)
  }
}

nonisolated enum WorkflowHistoryOutputPreview {
  static func json(_ outputs: [String: WorkflowJSONValue]) -> String {
    outputs.keys.sorted().prefix(8).map { key in
      "\(key): \(preview(outputs[key]!, depth: 0))"
    }.joined(separator: "\n")
  }

  private static func preview(_ value: WorkflowJSONValue, depth: Int) -> String {
    switch value {
    case .string(let value): String(value.prefix(300))
    case .object(let fields):
      depth >= 2
        ? "{…}"
        : "{"
          + fields.keys.sorted().prefix(6).map {
            "\($0): \(preview(fields[$0]!, depth: depth + 1))"
          }.joined(separator: ", ") + "}"
    case .array(let values):
      depth >= 2 ? "[…]" : "[" + values.prefix(6).map { preview($0, depth: depth + 1) }.joined(separator: ", ") + "]"
    default: (try? String(bytes: JSONEncoder().encode(value), encoding: .utf8)) ?? "null"
    }
  }
}

nonisolated enum WorkflowHistoryOutputIntent: Equatable, Sendable {
  case openFile(URL)
  case copyFile(URL)
  case reveal(URL)
  case openText(String, String)
  case openJSON([String: WorkflowJSONValue])
  case copyJSON([String: WorkflowJSONValue])
  case keep(URL)
  case export(URL)
}
