// ProwlCLI/Commands/SelectorOptions.swift
// Shared target selector options for commands that support them.

import ArgumentParser
import ProwlCLIShared

struct SelectorOptions: ParsableArguments {
  @Option(name: .shortAndLong, help: "Auto-resolve target by pane/tab UUID or worktree id/name/path.")
  var target: String?

  @Option(name: .long, help: "Target worktree by id, name, or path.")
  var worktree: String?

  @Option(name: .long, help: "Target tab by id.")
  var tab: String?

  @Option(name: .long, help: "Target pane by id.")
  var pane: String?

  /// Validate mutual exclusivity and return typed selector.
  func resolve() throws -> TargetSelector {
    let provided = [target, worktree, tab, pane].compactMap { $0 }
    guard provided.count <= 1 else {
      throw ExitError(
        code: CLIErrorCode.invalidArgument,
        message: "At most one target selector (--target, --worktree, --tab, --pane) is allowed."
      )
    }
    if let a = target { return .auto(a) }
    if let w = worktree { return .worktree(w) }
    if let t = tab { return .tab(t) }
    if let p = pane { return .pane(p) }
    return .none
  }

  /// Resolve with an additional auto-target value (from positional argument).
  /// The positional target takes effect only when no flag selectors are specified.
  func resolve(positionalTarget: String?) throws -> TargetSelector {
    let flagSelector = try resolve()
    if case .none = flagSelector, let positional = positionalTarget {
      return .auto(positional)
    }
    return flagSelector
  }
}
