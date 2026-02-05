enum SidebarSelection: Hashable {
  case worktree(Worktree.ID)
  case repository(Repository.ID)
  case archivedWorktrees

  var worktreeID: Worktree.ID? {
    switch self {
    case .worktree(let id):
      return id
    case .repository:
      return nil
    case .archivedWorktrees:
      return nil
    }
  }
}
