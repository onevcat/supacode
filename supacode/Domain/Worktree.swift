import Foundation

struct Worktree: Identifiable, Hashable {
  let id: String
  let name: String
  let detail: String
  let workingDirectory: URL
  let repositoryRootURL: URL
}
