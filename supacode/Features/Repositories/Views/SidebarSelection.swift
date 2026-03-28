enum SidebarSelection: Hashable {
  case worktree(Worktree.ID)
  case archivedWorktrees

  var worktreeID: Worktree.ID? {
    switch self {
    case .worktree(let id):
      return id
    case .archivedWorktrees:
      return nil
    }
  }
}
