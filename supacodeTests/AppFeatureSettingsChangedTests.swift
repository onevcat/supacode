import ComposableArchitecture
import DependenciesTestSupport
import Testing

@testable import supacode

@MainActor
struct AppFeatureSettingsChangedTests {
  @Test(.dependencies) func settingsChangedPropagatesRepositorySettings() async {
    var settings = GlobalSettings.default
    settings.githubIntegrationEnabled = false
    settings.automaticallyArchiveMergedWorktrees = true
    settings.moveNotifiedWorktreeToTop = false
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.settings(.delegate(.settingsChanged(settings))))
    await store.receive(\.repositories.setGithubIntegrationEnabled) {
      $0.repositories.githubIntegrationAvailability = .disabled
    }
    await store.receive(\.repositories.setAutomaticallyArchiveMergedWorktrees) {
      $0.repositories.automaticallyArchiveMergedWorktrees = true
    }
    await store.receive(\.repositories.setMoveNotifiedWorktreeToTop) {
      $0.repositories.moveNotifiedWorktreeToTop = false
    }
    await store.receive(\.updates.applySettings) {
      $0.updates.didConfigureUpdates = true
    }
    await store.finish()
  }

  @Test(.dependencies) func terminalFontSizeEventDoesNotFanOutGlobalSettingsEffects() async {
    let sentTerminalCommands = LockIsolated<[TerminalClient.Command]>([])
    let watcherCommands = LockIsolated<[WorktreeInfoWatcherClient.Command]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sentTerminalCommands.withValue { $0.append(command) }
      }
      $0.worktreeInfoWatcher.send = { command in
        watcherCommands.withValue { $0.append(command) }
      }
    }

    await store.send(.terminalEvent(.fontSizeChanged(18)))
    await store.receive(\.settings.setTerminalFontSize) {
      $0.settings.terminalFontSize = 18
    }
    await store.receive(\.settings.delegate.terminalFontSizeChanged)
    await store.finish()

    #expect(sentTerminalCommands.value.isEmpty)
    #expect(watcherCommands.value.isEmpty)
  }

  @Test(.dependencies) func clearTerminalLayoutSnapshotShowsSuccessToast() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.settings(.delegate(.terminalLayoutSnapshotCleared(success: true))))
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .success("Saved terminal layout cleared")
    }
    await store.skipInFlightEffects()
  }
}
