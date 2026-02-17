import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureDefaultEditorTests {
  @Test(.dependencies) func defaultEditorAppliesToAutomaticRepositorySettings() async {
    let worktree = makeWorktree()
    let repositoriesState = makeRepositoriesState(worktree: worktree)
    let storage = SettingsTestStorage()
    let settingsFileURL = URL(
      fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json"
    )
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
    } operation: {
      var settings = GlobalSettings.default
      settings.defaultEditorID = OpenWorktreeAction.finder.settingsID
      @Shared(.settingsFile) var settingsFile
      $settingsFile.withLock { $0.global = settings }
      return TestStore(
        initialState: AppFeature.State(
          repositories: repositoriesState,
          settings: SettingsFeature.State(settings: settings)
        )
      ) {
        AppFeature()
      }
    }

    await store.send(.repositories(.delegate(.selectedWorktreeChanged(worktree))))
    await store.receive(\.worktreeSettingsLoaded)
    #expect(store.state.openActionSelection == .finder)
    #expect(store.state.selectedRunScript == "")
    await store.finish()
  }

  @Test(.dependencies) func selectedWorktreeChangedOnlyUpdatesWatcherSelection() async {
    let worktree = makeWorktree()
    let repositoriesState = makeRepositoriesState(worktree: worktree)
    let watcherCommands = LockIsolated<[WorktreeInfoWatcherClient.Command]>([])
    let storage = SettingsTestStorage()
    let settingsFileURL = URL(
      fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json"
    )
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.repositoryPersistence.saveLastFocusedWorktreeID = { _ in }
      $0.terminalClient.send = { _ in }
      $0.worktreeInfoWatcher.send = { command in
        watcherCommands.withValue { $0.append(command) }
      }
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
    }

    await store.send(.repositories(.delegate(.selectedWorktreeChanged(worktree))))
    await store.receive(\.worktreeSettingsLoaded) {
      $0.openActionSelection = .zed
    }
    await store.finish()

    #expect(watcherCommands.value == [.setSelectedWorktreeID(worktree.id)])
  }

  private func makeWorktree() -> Worktree {
    let repositoryRootURL = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")
    let worktreeURL = repositoryRootURL.appending(path: "wt-1")
    return Worktree(
      id: worktreeURL.path(percentEncoded: false),
      name: "wt-1",
      detail: "detail",
      workingDirectory: worktreeURL,
      repositoryRootURL: repositoryRootURL
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: worktree.repositoryRootURL.path(percentEncoded: false),
      rootURL: worktree.repositoryRootURL,
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.selection = .worktree(worktree.id)
    return repositoriesState
  }
}
