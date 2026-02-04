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

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.selection = .worktree(worktree.id)
    return repositoriesState
  }
}
