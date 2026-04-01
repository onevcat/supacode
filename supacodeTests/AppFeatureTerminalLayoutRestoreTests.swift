import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import SwiftUI
import Testing

@testable import supacode

@MainActor
struct AppFeatureTerminalLayoutRestoreTests {
  @Test(.dependencies) func repositoriesChangedRestoresLayoutOnceWhenEnabled() async {
    let worktree = makeWorktree()
    let repository = makeRepository(worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State(repositories: [repository])
    repositoriesState.snapshotPersistencePhase = .active
    var settings = SettingsFeature.State()
    settings.restoreTerminalLayoutOnLaunch = true
    let sentCommands = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(repositories: repositoriesState, settings: settings)
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentCommands.withValue { $0.append(command) }
      }
      $0.worktreeInfoWatcher.send = { _ in }
    }
    store.exhaustivity = .off

    await store.send(.repositories(.delegate(.repositoriesChanged([repository])))) {
      $0.launchRestoreMode = .lastFocusedWorktree
      $0.repositories.selection = nil
    }
    await store.finish()

    #expect(
      sentCommands.value.contains(
        .restoreLayoutSnapshot(worktrees: [worktree])
      )
    )
  }

  @Test(.dependencies) func repositoriesChangedSkipsRestoreWhenDisabled() async {
    let worktree = makeWorktree()
    let repository = makeRepository(worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State(repositories: [repository])
    repositoriesState.snapshotPersistencePhase = .active
    let sentCommands = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentCommands.withValue { $0.append(command) }
      }
      $0.worktreeInfoWatcher.send = { _ in }
    }
    store.exhaustivity = .off

    await store.send(.repositories(.delegate(.repositoriesChanged([repository]))))
    await store.finish()

    #expect(
      sentCommands.value.contains {
        if case .restoreLayoutSnapshot = $0 {
          return true
        }
        return false
      } == false
    )
  }

  @Test(.dependencies) func restoreOnlyTriggersOnce() async {
    let worktree = makeWorktree()
    let repository = makeRepository(worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State(repositories: [repository])
    repositoriesState.snapshotPersistencePhase = .active
    var settings = SettingsFeature.State()
    settings.restoreTerminalLayoutOnLaunch = true
    let sentCommands = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(repositories: repositoriesState, settings: settings)
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentCommands.withValue { $0.append(command) }
      }
      $0.worktreeInfoWatcher.send = { _ in }
    }
    store.exhaustivity = .off

    // First repositoriesChanged triggers restore and flips mode
    await store.send(.repositories(.delegate(.repositoriesChanged([repository])))) {
      $0.launchRestoreMode = .lastFocusedWorktree
      $0.repositories.selection = nil
    }
    await store.finish()

    sentCommands.withValue { $0.removeAll() }

    // Second repositoriesChanged should NOT trigger restore
    await store.send(.repositories(.delegate(.repositoriesChanged([repository]))))
    await store.finish()

    #expect(
      sentCommands.value.contains {
        if case .restoreLayoutSnapshot = $0 {
          return true
        }
        return false
      } == false
    )
  }

  @Test(.dependencies) func layoutRestoredEventSelectsWorktree() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.terminalEvent(.layoutRestored(selectedWorktreeID: "/tmp/repo/wt-1")))
    await store.receive(\.repositories.selectWorktree)
  }

  @Test(.dependencies) func scenePhaseInactiveSavesLayoutSnapshot() async {
    let sentCommands = LockIsolated<[TerminalClient.Command]>([])
    var settings = SettingsFeature.State()
    settings.restoreTerminalLayoutOnLaunch = true
    let store = TestStore(initialState: AppFeature.State(settings: settings)) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentCommands.withValue { $0.append(command) }
      }
    }
    store.exhaustivity = .off

    await store.send(.scenePhaseChanged(.inactive))
    await store.finish()

    #expect(sentCommands.value == [.saveLayoutSnapshot])
  }

  @Test(.dependencies) func scenePhaseInactiveSkipsSaveWhenRestoreDisabled() async {
    let sentCommands = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentCommands.withValue { $0.append(command) }
      }
    }
    store.exhaustivity = .off

    await store.send(.scenePhaseChanged(.inactive))
    await store.finish()

    #expect(!sentCommands.value.contains(.saveLayoutSnapshot))
  }
}

private func makeWorktree() -> Worktree {
  Worktree(
    id: "/tmp/repo/wt-1",
    name: "wt-1",
    detail: "",
    workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
    repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
  )
}

private func makeRepository(worktrees: [Worktree]) -> Repository {
  Repository(
    id: "/tmp/repo",
    rootURL: URL(fileURLWithPath: "/tmp/repo"),
    name: "repo",
    worktrees: IdentifiedArray(uniqueElements: worktrees)
  )
}
