import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct AppFeatureCommandPaletteTests {
  @Test(.dependencies) func openSettingsShowsWindow() async {
    let shown = LockIsolated(false)
    var state = AppFeature.State()
    state.settings.selection = .updates
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.settingsWindowClient.show = {
        shown.withValue { $0 = true }
      }
    }

    await store.send(.commandPalette(.delegate(.openSettings)))
    await store.receive(\.settings.setSelection) {
      $0.settings.selection = .general
    }
    await store.finish()
    #expect(shown.value)
  }

  @Test(.dependencies) func newWorktreeDispatchesCreateRandomWorktree() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Unable to create worktree")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("OK")
      }
    } message: {
      TextState("Open a repository to create a worktree.")
    }

    await store.send(.commandPalette(.delegate(.newWorktree)))
    await store.receive(\.repositories.createRandomWorktree) {
      $0.repositories.alert = expectedAlert
    }
  }

  @Test(.dependencies) func removeWorktreeDispatchesRequest() async {
    let worktree = makeWorktree(
      id: "/tmp/repo-run/wt-1",
      name: "wt-1",
      repoRoot: "/tmp/repo-run"
    )
    let repository = makeRepository(id: "/tmp/repo-run", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("🚨 Delete worktree?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDeleteWorktree(worktree.id, repository.id)) {
        TextState("Delete (⌘↩)")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Delete \(worktree.name)? This deletes the worktree directory and its local branch.")
    }

    await store.send(.commandPalette(.delegate(.removeWorktree(worktree.id, repository.id))))
    await store.receive(\.repositories.requestDeleteWorktree) {
      $0.repositories.alert = expectedAlert
    }
  }

  @Test(.dependencies) func archiveWorktreeDispatchesRequest() async {
    let worktree = makeWorktree(
      id: "/tmp/repo-archive/wt-1",
      name: "wt-1",
      repoRoot: "/tmp/repo-archive"
    )
    let repository = makeRepository(id: "/tmp/repo-archive", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Archive worktree?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmArchiveWorktree(worktree.id, repository.id)) {
        TextState("Archive (⌘↩)")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Archive \(worktree.name)?")
    }

    await store.send(.commandPalette(.delegate(.archiveWorktree(worktree.id, repository.id))))
    await store.receive(\.repositories.requestArchiveWorktree) {
      $0.repositories.alert = expectedAlert
    }
  }

  @Test(.dependencies) func runWorktreeUsesRepositoryRunScript() async {
    let worktree = makeWorktree(
      id: "/tmp/repo-run/wt-1",
      name: "wt-1",
      repoRoot: "/tmp/repo-run"
    )
    let repository = makeRepository(id: "/tmp/repo-run", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let storage = SettingsFileStorage.inMemory()
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    withDependencies {
      $0.settingsFileStorage = storage
    } operation: {
      @Shared(.repositorySettings(worktree.repositoryRootURL)) var repositorySettings
      $repositorySettings.withLock {
        $0.runScript = "make run"
        $0.openActionID = "finder"
      }
    }

    await store.send(.commandPalette(.delegate(.runWorktree(worktree.id))))
    await store.receive(\.repositories.selectWorktree) {
      $0.repositories.selection = .worktree(worktree.id)
    }
    await store.receive(\.repositories.delegate.selectedWorktreeChanged)
    await store.receive(\.worktreeSettingsLoaded) {
      $0.openActionSelection = .finder
      $0.selectedRunScript = "make run"
    }
    await store.finish()
    #expect(sent.value.contains(.runScript(worktree, script: "make run")))
  }

  @Test(.dependencies) func openWorktreeInEditorUsesResolver() async {
    let worktree = makeWorktree(
      id: "/tmp/repo-editor/wt-1",
      name: "wt-1",
      repoRoot: "/tmp/repo-editor"
    )
    let repository = makeRepository(id: "/tmp/repo-editor", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let opened = LockIsolated<[(OpenWorktreeAction, Worktree)]>([])
    let storage = SettingsFileStorage.inMemory()
    var initialState = AppFeature.State(
      repositories: repositoriesState,
      settings: SettingsFeature.State()
    )
    initialState.openActionSelection = .terminal
    initialState.selectedRunScript = "previous"
    let store = TestStore(initialState: initialState) {
      AppFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage
      $0.editorActionResolver.resolve = { .vscode }
      $0.workspaceClient.open = { action, worktree, _ in
        opened.withValue { $0.append((action, worktree)) }
      }
    }

    withDependencies {
      $0.settingsFileStorage = storage
    } operation: {
      @Shared(.repositorySettings(worktree.repositoryRootURL)) var repositorySettings
      $repositorySettings.withLock {
        $0.openActionID = "finder"
        $0.runScript = ""
      }
    }

    await store.send(.commandPalette(.delegate(.openWorktreeInEditor(worktree.id))))
    await store.receive(\.repositories.selectWorktree) {
      $0.repositories.selection = .worktree(worktree.id)
    }
    await store.receive(\.repositories.delegate.selectedWorktreeChanged)
    await store.receive(\.worktreeSettingsLoaded) {
      $0.openActionSelection = .finder
      $0.selectedRunScript = ""
    }
    await store.finish()
    #expect(opened.value.count == 1)
    #expect(opened.value.first?.0 == .vscode)
    #expect(opened.value.first?.1 == worktree)
  }
}

private func makeWorktree(id: String, name: String, repoRoot: String = "/tmp/repo") -> Worktree {
  Worktree(
    id: id,
    name: name,
    detail: "detail",
    workingDirectory: URL(fileURLWithPath: id),
    repositoryRootURL: URL(fileURLWithPath: repoRoot)
  )
}

private func makeRepository(id: String, worktrees: [Worktree]) -> Repository {
  Repository(
    id: id,
    rootURL: URL(fileURLWithPath: id),
    name: "repo",
    worktrees: IdentifiedArray(uniqueElements: worktrees)
  )
}
