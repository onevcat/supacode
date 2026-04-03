// ProwlCLI/Output/OutputRenderer.swift
// Renders command responses for terminal output.

import Foundation
import ProwlCLIShared
import Rainbow

enum OutputRenderer {
  static func render(_ response: CommandResponse, mode: OutputMode) {
    switch mode {
    case .json:
      renderJSON(response)
    case .text:
      renderText(response)
    }
  }

  static func renderError(code: String, message: String, command: String, mode: OutputMode) {
    let response = CommandResponse(
      ok: false,
      command: command,
      schemaVersion: "prowl.cli.\(command).v1",
      error: CommandError(code: code, message: message)
    )
    render(response, mode: mode)
  }

  // MARK: - JSON

  private static func renderJSON(_ response: CommandResponse) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(response),
       let jsonString = String(data: data, encoding: .utf8)
    {
      print(jsonString)
    }
  }

  // MARK: - Text

  private static func renderText(_ response: CommandResponse) {
    if response.ok {
      if response.command == "list",
         let data = response.data,
         let payload = try? data.decode(as: ListCommandPayload.self)
      {
        print(renderList(payload))
        return
      }

      if response.command == "send",
         let data = response.data,
         let payload = try? data.decode(as: SendCommandPayload.self)
      {
        print(renderSend(payload))
        return
      }

      if response.command == "focus",
         let data = response.data,
         let payload = try? data.decode(as: FocusCommandPayload.self)
      {
        print(renderFocus(payload))
        return
      }

      print("ok: \(response.command)")
      return
    }

    if let error = response.error {
      FileHandle.standardError.write(
        Data("error [\(error.code)]: \(error.message)\n".utf8)
      )
    }
  }

  private static func renderList(_ payload: ListCommandPayload) -> String {
    guard !payload.items.isEmpty else {
      return "No panes found."
    }

    // Group items by worktree, preserving order of first appearance.
    var worktreeOrder: [String] = []
    var worktreeGroups: [String: [ListCommandItem]] = [:]
    for item in payload.items {
      let key = item.worktree.id
      if worktreeGroups[key] == nil {
        worktreeOrder.append(key)
      }
      worktreeGroups[key, default: []].append(item)
    }

    var lines: [String] = []

    for (index, worktreeID) in worktreeOrder.enumerated() {
      guard let items = worktreeGroups[worktreeID], let first = items.first else { continue }

      if index > 0 {
        lines.append("")
      }

      // Worktree header: "ProjectName:branch (status)"
      let projectName = projectName(from: first.worktree.path)
      let statusText: String
      switch first.task.status {
      case .running:
        statusText = "running".green
      case .idle:
        statusText = "idle".dim
      case nil:
        statusText = "n/a".dim
      }
      lines.append(
        "\(projectName.cyan.bold)\(":".dim)\(first.worktree.name) (\(statusText))  \(first.worktree.id.dim)"
      )
      lines.append("  \("path:".dim) \(first.worktree.path)")

      // Group panes by tab within this worktree.
      var tabOrder: [String] = []
      var tabGroups: [String: [ListCommandItem]] = [:]
      for item in items {
        let tabKey = item.tab.id
        if tabGroups[tabKey] == nil {
          tabOrder.append(tabKey)
        }
        tabGroups[tabKey, default: []].append(item)
      }

      let worktreePath = normalizeTrailingSlash(first.worktree.path)

      for (tabIndex, tabID) in tabOrder.enumerated() {
        guard let tabItems = tabGroups[tabID], let firstTab = tabItems.first else { continue }

        let tabNum = "Tab \(tabIndex + 1):"
        let selectedMark = firstTab.tab.selected ? "*".yellow : " "
        let tabTitle = firstTab.tab.selected ? firstTab.tab.title.yellow : firstTab.tab.title
        lines.append("  [\(selectedMark)] \(tabNum.dim) \(tabTitle)")

        for (paneIndex, item) in tabItems.enumerated() {
          let focusMark = item.pane.focused ? ">".green.bold : " "
          let paneNum = item.pane.focused ? "Pane \(paneIndex + 1):".green : "Pane \(paneIndex + 1):".dim
          let paneTitle = item.pane.focused ? item.pane.title.green.bold : item.pane.title.dim

          var paneLine = "      \(focusMark) \(paneNum) \(paneTitle)"

          // Only show cwd when it differs from the worktree path.
          if let cwd = item.pane.cwd, normalizeTrailingSlash(cwd) != worktreePath {
            paneLine += "  \(cwd.dim)"
          }

          paneLine += "  \(item.pane.id.dim)"
          lines.append(paneLine)
        }
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func renderSend(_ payload: SendCommandPayload) -> String {
    let wt = payload.target.worktree
    let pane = payload.target.pane
    let input = payload.input

    let projectName = projectName(from: wt.path)
    var lines: [String] = []

    lines.append(
      "Sent to \(projectName.cyan.bold)\(":".dim)\(wt.name) → \(pane.title.green)"
      + "  \(pane.id.dim)"
    )

    let enterLabel = input.trailingEnterSent ? "yes".green : "no".dim
    lines.append(
      "  \("source:".dim) \(input.source)"
      + "  \("chars:".dim) \(input.characters)"
      + "  \("bytes:".dim) \(input.bytes)"
      + "  \("enter:".dim) \(enterLabel)"
    )

    if let wait = payload.wait {
      let exitLabel: String
      if let code = wait.exitCode {
        exitLabel = code == 0 ? "0".green : "\(code)".red.bold
      } else {
        exitLabel = "n/a".dim
      }
      let durationLabel = formatDurationMs(wait.durationMs)
      lines.append("  \("exit:".dim) \(exitLabel)  \("duration:".dim) \(durationLabel)")
    } else {
      lines.append("  \("wait:".dim) \("none (fire-and-forget)".dim)")
    }

    return lines.joined(separator: "\n")
  }

  private static func renderFocus(_ payload: FocusCommandPayload) -> String {
    let wt = payload.target.worktree
    let tab = payload.target.tab
    let pane = payload.target.pane

    let projectName = projectName(from: wt.path)
    let frontLabel = payload.broughtToFront ? "yes".green : "no".red.bold
    let requestedValue = payload.requested.value ?? "current"

    var lines: [String] = []
    lines.append(
      "Focused \(projectName.cyan.bold)\(":".dim)\(wt.name) → \(pane.title.green)"
      + "  \(pane.id.dim)"
    )
    lines.append(
      "  \("requested:".dim) \(payload.requested.selector.rawValue)=\(requestedValue)"
      + "  \("resolved:".dim) \(payload.resolvedVia.rawValue)"
      + "  \("front:".dim) \(frontLabel)"
    )
    lines.append("  \("tab:".dim) \(tab.title)  \(tab.id.dim)")
    if let cwd = pane.cwd {
      lines.append("  \("cwd:".dim) \(cwd)")
    }
    return lines.joined(separator: "\n")
  }

  private static func formatDurationMs(_ ms: Int) -> String {
    if ms < 1000 {
      return "\(ms)ms"
    }
    let seconds = ms / 1000
    if seconds < 60 {
      return "\(seconds).\(String(format: "%03d", ms % 1000))s"
    }
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return remainingSeconds > 0 ? "\(minutes)m \(remainingSeconds)s" : "\(minutes)m"
  }

  private static func projectName(from path: String) -> String {
    let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
    return trimmed.split(separator: "/").last.map(String.init) ?? path
  }

  private static func normalizeTrailingSlash(_ path: String) -> String {
    path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
