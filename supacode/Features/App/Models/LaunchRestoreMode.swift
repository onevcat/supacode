enum LaunchRestoreMode: Equatable, Sendable {
  case lastFocusedWorktree
  case restoreLayout
  // case openWorktree(Worktree.ID)  // future CLI support
}
