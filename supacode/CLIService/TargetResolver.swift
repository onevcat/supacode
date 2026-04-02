// supacode/CLIService/TargetResolver.swift
// Resolves target selectors against current app state.
// Scaffold — actual resolution depends on wiring to WorktreeTerminalManager.

import Foundation

@MainActor
final class TargetResolver {
  /// Resolve a target selector to concrete worktree/tab/pane IDs.
  /// Returns nil if the target cannot be found.
  func resolve(_ selector: TargetSelector) -> ResolvedTarget? {
    // Scaffold: resolution not yet wired to WorktreeTerminalManager.
    // Will be implemented when command handlers are built out.
    switch selector {
    case .none:
      return nil
    case .worktree, .tab, .pane:
      return nil
    }
  }
}

/// Placeholder for resolved target information.
/// Will be populated with actual worktree/tab/pane data when wired.
struct ResolvedTarget {
  let worktreeID: String
  let tabID: String
  let paneID: String
}
