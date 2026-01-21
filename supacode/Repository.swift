import Foundation

struct Repository: Identifiable, Hashable {
  let id: String
  let rootURL: URL
  let name: String
  let initials: String
  let githubOwner: String?
  let worktrees: [Worktree]
}
