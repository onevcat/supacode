import ComposableArchitecture
import Foundation

struct GitClientDependency {
  var repoRoot: @Sendable (URL) async throws -> URL
  var worktrees: @Sendable (URL) async throws -> [Worktree]
  var localBranchNames: @Sendable (URL) async throws -> Set<String>
  var createWorktree: @Sendable (_ name: String, _ repoRoot: URL) async throws -> Worktree
  var syncWorktree: @Sendable (_ worktreeURL: URL, _ copyIgnored: Bool, _ copyUntracked: Bool) async throws -> Void
  var isWorktreeDirty: @Sendable (URL) async -> Bool
  var removeWorktree: @Sendable (_ worktree: Worktree) async throws -> URL
  var branchName: @Sendable (URL) async -> String?
  var lineChanges: @Sendable (URL) async -> (added: Int, removed: Int)?
  var renameBranch: @Sendable (_ worktreeURL: URL, _ branchName: String) async throws -> Void
}

extension GitClientDependency: DependencyKey {
  static let liveValue = GitClientDependency(
    repoRoot: { try await GitClient().repoRoot(for: $0) },
    worktrees: { try await GitClient().worktrees(for: $0) },
    localBranchNames: { try await GitClient().localBranchNames(for: $0) },
    createWorktree: { name, repoRoot in
      try await GitClient().createWorktree(named: name, in: repoRoot)
    },
    syncWorktree: { worktreeURL, copyIgnored, copyUntracked in
      try await GitClient().syncWorktree(
        at: worktreeURL,
        copyIgnored: copyIgnored,
        copyUntracked: copyUntracked
      )
    },
    isWorktreeDirty: { await GitClient().isWorktreeDirty(at: $0) },
    removeWorktree: { worktree in
      try await GitClient().removeWorktree(worktree)
    },
    branchName: { await GitClient().branchName(for: $0) },
    lineChanges: { await GitClient().lineChanges(at: $0) },
    renameBranch: { worktreeURL, branchName in
      try await GitClient().renameBranch(in: worktreeURL, to: branchName)
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
