import Foundation

struct PendingWorktree: Identifiable, Hashable {
  let id: String
  let repositoryID: Repository.ID
  let name: String
  let detail: String
}
