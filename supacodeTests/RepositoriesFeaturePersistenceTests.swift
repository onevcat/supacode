import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct RepositoriesFeaturePersistenceTests {
  @Test(.dependencies) func taskLoadsPinnedWorktreesBeforeRepositories() async {
    let pinned = ["/tmp/repo/wt-1"]
    let store = TestStore(initialState: RepositoriesFeature.State()) {
      RepositoriesFeature()
    } withDependencies: {
      $0.repositoryPersistence = RepositoryPersistenceClient(
        loadRoots: { [] },
        saveRoots: { _ in },
        loadPinnedWorktreeIDs: { pinned },
        savePinnedWorktreeIDs: { _ in },
        loadLastFocusedWorktreeID: { nil },
        saveLastFocusedWorktreeID: { _ in }
      )
    }

    await store.send(.task)
    await store.receive(.pinnedWorktreeIDsLoaded(pinned)) {
      $0.pinnedWorktreeIDs = pinned
    }
    await store.receive(.lastFocusedWorktreeIDLoaded(nil)) {
      $0.lastFocusedWorktreeID = nil
      $0.shouldRestoreLastFocusedWorktree = true
    }
    await store.receive(.loadPersistedRepositories)
    await store.receive(.repositoriesLoaded([], failures: [], roots: [], animated: false)) {
      $0.repositories = []
      $0.pinnedWorktreeIDs = []
      $0.shouldRestoreLastFocusedWorktree = false
    }
    await store.receive(.delegate(.repositoriesChanged([])))
    await store.finish()
  }
}
