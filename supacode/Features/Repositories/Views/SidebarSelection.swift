import Foundation

enum SidebarSelection: Hashable {
  case worktree(Worktree.ID)
  case archivedWorktrees
  case repository(Repository.ID)
  case canvas
  case remoteEndpoint(UUID)
  case remoteGroup(endpointID: UUID, group: String)

  var worktreeID: Worktree.ID? {
    switch self {
    case .worktree(let id):
      return id
    case .archivedWorktrees, .repository, .canvas, .remoteEndpoint, .remoteGroup:
      return nil
    }
  }
}
