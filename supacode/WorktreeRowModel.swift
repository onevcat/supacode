import Foundation

struct WorktreeRowModel: Identifiable, Hashable {
  let id: String
  let repositoryID: Repository.ID
  let name: String
  let detail: String
  let isPinned: Bool
  let isPending: Bool
  let isDeleting: Bool
  let isRemovable: Bool
}
