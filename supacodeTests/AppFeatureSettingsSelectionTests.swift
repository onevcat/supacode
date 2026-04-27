import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
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

  @Test(.dependencies) func selectingRepositorySeedsAppearanceSynchronously() async {
    // Regression: selecting a repo whose appearance is already in
    // @Shared used to construct a State with `.empty` appearance and
    // load asynchronously via .task. The async hop raced with the
    // user's first click, sometimes wiping previously-saved fields.
    // The State must now carry the appearance from frame zero.
    let storage = SettingsTestStorage()
    let appearancesURL = URL(fileURLWithPath: "/tmp/appearances-\(UUID().uuidString).json")
    let savedAppearance = RepositoryAppearance(
      icon: .sfSymbol("hammer.fill"), color: .blue
    )
    let repository = Repository(
      id: "appearance-repo",
      rootURL: URL(fileURLWithPath: "/tmp/appearance-repo"),
      name: "AppearanceRepo",
      worktrees: []
    )

    await withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.repositoryAppearancesFileURL = appearancesURL
    } operation: {
      @Shared(.repositoryAppearances) var appearances
      $appearances.withLock {
        $0[repository.id] = savedAppearance
      }

      let store = TestStore(
        initialState: AppFeature.State(
          repositories: RepositoriesFeature.State(repositories: [repository]),
          settings: SettingsFeature.State()
        )
      ) {
        AppFeature()
      } withDependencies: {
        $0.settingsFileStorage = storage.storage
        $0.repositoryAppearancesFileURL = appearancesURL
      }

      await store.send(.settings(.setSelection(.repository(repository.id)))) {
        $0.settings.selection = .repository(repository.id)
        $0.settings.repositorySettings = RepositorySettingsFeature.State(
          rootURL: repository.rootURL,
          repositoryID: repository.id,
          repositoryKind: repository.kind,
          settings: .default,
          userSettings: .default,
          appearance: savedAppearance
        )
      }
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
