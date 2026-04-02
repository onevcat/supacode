// ProwlCLI/Commands/SelectorOptions.swift
// Shared target selector options for commands that support them.

import ArgumentParser

struct SelectorOptions: ParsableArguments {
  @Option(name: .long, help: "Target worktree by id, name, or path.")
  var worktree: String?

  @Option(name: .long, help: "Target tab by id.")
  var tab: String?

  @Option(name: .long, help: "Target pane by id.")
  var pane: String?

  /// Validate mutual exclusivity and return typed selector.
  func resolve() throws -> TargetSelector {
    let provided = [worktree, tab, pane].compactMap { $0 }
    guard provided.count <= 1 else {
      throw ValidationError(
        "At most one target selector (--worktree, --tab, --pane) is allowed."
      )
    }
    if let w = worktree { return .worktree(w) }
    if let t = tab { return .tab(t) }
    if let p = pane { return .pane(p) }
    return .none
  }
}
