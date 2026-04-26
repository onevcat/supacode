import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureSettingsSelectionTests {
  @Test func selectingRepositoryCreatesRepositorySettingsState() async {
    let repository = Repository(
      id: "repo-id",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "Repo",
      worktrees: []
    )
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: [repository]),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository(repository.id)))) {
      $0.settings.selection = .repository(repository.id)
      $0.settings.repositorySettings = RepositorySettingsFeature.State(
        rootURL: repository.rootURL,
        repositoryID: repository.id,
        repositoryKind: repository.kind,
        settings: .default,
        userSettings: .default
      )
    }
  }

  @Test func selectingMissingRepositoryClearsRepositorySettingsState() async {
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: []),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository("missing")))) {
      $0.settings.selection = .repository("missing")
      $0.settings.repositorySettings = nil
    }
  }

  @Test func selectingPlainRepositoryCreatesPlainRepositorySettingsState() async {
    let repository = Repository(
      id: "folder-id",
      rootURL: URL(fileURLWithPath: "/tmp/folder"),
      name: "Folder",
      kind: .plain,
      worktrees: []
    )
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(repositories: [repository]),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.repository(repository.id)))) {
      $0.settings.selection = .repository(repository.id)
      $0.settings.repositorySettings = RepositorySettingsFeature.State(
        rootURL: repository.rootURL,
        repositoryID: repository.id,
        repositoryKind: .plain,
        settings: .default,
        userSettings: .default
      )
    }
  }

  @Test func selectingNonRepositoryClearsRepositorySettingsState() async {
    let repository = Repository(
      id: "repo-id",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "Repo",
      worktrees: []
    )
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(repositories: [repository]),
      settings: SettingsFeature.State()
    )
    state.settings.selection = .repository(repository.id)
    state.settings.repositorySettings = RepositorySettingsFeature.State(
      rootURL: repository.rootURL,
      repositoryKind: repository.kind,
      settings: .default,
      userSettings: .default
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.settings(.setSelection(.general))) {
      $0.settings.selection = .general
      $0.settings.repositorySettings = nil
    }
  }
}
