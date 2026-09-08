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

nonisolated struct WorkflowHistoryStepGroup: Identifiable, Sendable {
  let id: String
  let title: String
  let state: String
  let iteration: Int?
  let attempts: [WorkflowRunRecord.Step]
  var legacyDetailsUnavailable = false
  var iterationLabel: String?

  var subtitle: String {
    var parts = [WorkflowHistoryStatus.label(state)]
    if let iterationLabel { parts.append(iterationLabel) } else if let iteration { parts.append("Round \(iteration)") }
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
    let deliveries = Dictionary(
      record.deliveries.values.map { ($0.ordinal, $0) }, uniquingKeysWith: { first, _ in first })
    let titles = Dictionary(definitions.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    let byStep = Dictionary(grouping: record.steps, by: \.id)
    var result: [(group: Self, order: [Int])] = []
    for definition in definitions {
      let records = byStep[definition.id] ?? []
      let byPath = Dictionary(grouping: records) { $0.iterationPath ?? $0.iteration.map { ["legacy:\($0)"] } ?? [] }
      let paths = byPath.isEmpty ? [[]] : Array(byPath.keys)
      for path in paths {
        let attempts = (byPath[path] ?? []).map { step in
          var step = step
          if step.delivery == nil, let ordinal = step.ordinal { step.delivery = deliveries[ordinal] }
          if record.stepDefinitions == nil, records.count == 1, step.state == .completed, step.outputs == nil {
            step.outputs = record.actions[step.id]
          }
          return step
        }
        let latest = attempts.last
        var state = latest?.state.rawValue ?? (record.run.status.isTerminal ? "not_run" : "pending")
        if latest?.state == .active && record.run.status.isTerminal { state = "interrupted" }
        if record.run.status.attention?.step == definition.id && latest?.state == .active { state = "needs_attention" }
        if latest?.state == .skipped && latest?.branchExcluded == true { state = "branch_not_selected" }
        let group = Self(
          id: "\(definition.id):\(path.joined(separator: "/"))",
          title: latest?.title ?? definition.title, state: state, iteration: latest?.iteration, attempts: attempts,
          legacyDetailsUnavailable: record.stepDefinitions == nil,
          iterationLabel: path.isEmpty || path.first?.hasPrefix("legacy:") == true
            ? nil
            : path.map { component in
              let parts = component.split(separator: ":")
              let loop = parts.first.map(String.init) ?? ""
              return "\(titles[loop] ?? loop) · Round \(parts.last ?? "?")"
            }.joined(separator: " / "))
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
    let text = outputs.keys.sorted().prefix(8).map { key in
      "\(bounded(key, limit: 100)): \(preview(outputs[key]!, depth: 0))"
    }.joined(separator: "\n")
    return bounded(text, limit: 4096)
  }

  static func text(_ data: Data, limit: Int = 4096) -> String? {
    let prefix = data.prefix(limit)
    if let value = String(bytes: prefix, encoding: .utf8) { return value }
    guard data.count > limit else { return nil }
    for count in 1...min(3, prefix.count) {
      let suffix = Array(prefix.suffix(count))
      let lead = suffix[0]
      let length =
        (0xC2...0xDF).contains(lead) ? 2 : (0xE0...0xEF).contains(lead) ? 3 : (0xF0...0xF4).contains(lead) ? 4 : 0
      guard count < length, suffix.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else { continue }
      if count > 1 {
        let second = suffix[1]
        if (lead == 0xE0 && second < 0xA0) || (lead == 0xED && second >= 0xA0)
          || (lead == 0xF0 && second < 0x90) || (lead == 0xF4 && second >= 0x90)
        {
          continue
        }
      }
      if let value = String(bytes: prefix.dropLast(count), encoding: .utf8) { return value }
    }
    return nil
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    let data = Data(value.utf8.prefix(limit + 4))
    return text(data, limit: limit) ?? ""
  }

  private static func preview(_ value: WorkflowJSONValue, depth: Int) -> String {
    switch value {
    case .string(let value): bounded(value, limit: 300)
    case .object(let fields):
      depth >= 2
        ? "{…}"
        : "{"
          + fields.keys.sorted().prefix(6).map {
            "\(bounded($0, limit: 100)): \(preview(fields[$0]!, depth: depth + 1))"
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
