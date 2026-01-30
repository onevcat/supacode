import ComposableArchitecture
import Foundation

struct GitClientDependency {
  var repoRoot: @Sendable (URL) async throws -> URL
  var worktrees: @Sendable (URL) async throws -> [Worktree]
  var localBranchNames: @Sendable (URL) async throws -> Set<String>
  var createWorktree:
    @Sendable (_ name: String, _ repoRoot: URL, _ copyIgnored: Bool, _ copyUntracked: Bool) async throws
      -> Worktree
  var removeWorktree: @Sendable (_ worktree: Worktree) async throws -> URL
  var branchName: @Sendable (URL) async -> String?
  var lineChanges: @Sendable (URL) async -> (added: Int, removed: Int)?
  var renameBranch: @Sendable (_ worktreeURL: URL, _ branchName: String) async throws -> Void
  var remoteInfo: @Sendable (_ repositoryRoot: URL) async -> GithubRemoteInfo?
}

extension GitClientDependency: DependencyKey {
  static let liveValue = GitClientDependency(
    repoRoot: { try await GitClient().repoRoot(for: $0) },
    worktrees: { try await GitClient().worktrees(for: $0) },
    localBranchNames: { try await GitClient().localBranchNames(for: $0) },
    createWorktree: { name, repoRoot, copyIgnored, copyUntracked in
      try await GitClient().createWorktree(
        named: name,
        in: repoRoot,
        copyIgnored: copyIgnored,
        copyUntracked: copyUntracked
      )
    },
    removeWorktree: { worktree in
      try await GitClient().removeWorktree(worktree)
    },
    branchName: { await GitClient().branchName(for: $0) },
    lineChanges: { await GitClient().lineChanges(at: $0) },
    renameBranch: { worktreeURL, branchName in
      try await GitClient().renameBranch(in: worktreeURL, to: branchName)
    },
    remoteInfo: { repositoryRoot in
      await GitClient().remoteInfo(for: repositoryRoot)
    }
  )
  static let testValue = liveValue
}

extension DependencyValues {
  var gitClient: GitClientDependency {
    get { self[GitClientDependency.self] }
    set { self[GitClientDependency.self] = newValue }
  }
}
