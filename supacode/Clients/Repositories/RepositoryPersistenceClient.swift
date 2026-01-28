import ComposableArchitecture

struct RepositoryPersistenceClient {
  var loadRoots: @Sendable () async -> [String]
  var saveRoots: @Sendable ([String]) async -> Void
  var loadPinnedWorktreeIDs: @Sendable () async -> [Worktree.ID]
  var savePinnedWorktreeIDs: @Sendable ([Worktree.ID]) async -> Void
}

extension RepositoryPersistenceClient: DependencyKey {
  static let liveValue: RepositoryPersistenceClient = {
    return RepositoryPersistenceClient(
      loadRoots: {
        await SettingsStorage.shared.load().repositoryRoots
      },
      saveRoots: { roots in
        await SettingsStorage.shared.update { settings in
          settings.repositoryRoots = roots
        }
      },
      loadPinnedWorktreeIDs: {
        await SettingsStorage.shared.load().pinnedWorktreeIDs
      },
      savePinnedWorktreeIDs: { ids in
        await SettingsStorage.shared.update { settings in
          settings.pinnedWorktreeIDs = ids
        }
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
