import ComposableArchitecture
import Foundation

struct GitClientDependency {
  var repoRoot: @Sendable (URL) async throws -> URL
  var worktrees: @Sendable (URL) async throws -> [Worktree]
  var localBranchNames: @Sendable (URL) async throws -> Set<String>
  var createWorktree: @Sendable (_ name: String, _ repoRoot: URL) async throws -> Worktree
  var isWorktreeDirty: @Sendable (URL) async throws -> Bool
  var removeWorktree: @Sendable (_ worktree: Worktree, _ force: Bool) async throws -> URL
}

extension GitClientDependency: DependencyKey {
  static let liveValue = GitClientDependency(
    repoRoot: { try await GitClient().repoRoot(for: $0) },
    worktrees: { try await GitClient().worktrees(for: $0) },
    localBranchNames: { try await GitClient().localBranchNames(for: $0) },
    createWorktree: { name, repoRoot in
      try await GitClient().createWorktree(named: name, in: repoRoot)
    },
    isWorktreeDirty: { try await GitClient().isWorktreeDirty(at: $0) },
    removeWorktree: { worktree, force in
      try await GitClient().removeWorktree(worktree, force: force)
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
