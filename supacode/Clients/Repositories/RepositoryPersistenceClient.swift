import ComposableArchitecture
import Foundation

struct RepositoryPersistenceClient {
  var loadRoots: @Sendable () -> [String]
  var saveRoots: @Sendable ([String]) -> Void
  var loadPinnedWorktreeIDs: @Sendable () -> [Worktree.ID]
  var savePinnedWorktreeIDs: @Sendable ([Worktree.ID]) -> Void
}

extension RepositoryPersistenceClient: DependencyKey {
  static let liveValue: RepositoryPersistenceClient = {
    let userDefaults = UserDefaults.standard
    let rootsKey = "repositories.roots"
    let pinnedKey = "repositories.worktrees.pinned"
    return RepositoryPersistenceClient(
      loadRoots: {
        guard let data = userDefaults.data(forKey: rootsKey) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
      },
      saveRoots: { roots in
        guard let data = try? JSONEncoder().encode(roots) else { return }
        userDefaults.set(data, forKey: rootsKey)
      },
      loadPinnedWorktreeIDs: {
        guard let data = userDefaults.data(forKey: pinnedKey) else { return [] }
        return (try? JSONDecoder().decode([Worktree.ID].self, from: data)) ?? []
      },
      savePinnedWorktreeIDs: { ids in
        guard let data = try? JSONEncoder().encode(ids) else { return }
        userDefaults.set(data, forKey: pinnedKey)
      }
    )
  }()
  static let testValue = RepositoryPersistenceClient(
    loadRoots: { [] },
    saveRoots: { _ in },
    loadPinnedWorktreeIDs: { [] },
    savePinnedWorktreeIDs: { _ in }
  )
}

extension DependencyValues {
  var repositoryPersistence: RepositoryPersistenceClient {
    get { self[RepositoryPersistenceClient.self] }
    set { self[RepositoryPersistenceClient.self] = newValue }
  }
}
