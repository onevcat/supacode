import ComposableArchitecture
import CustomDump
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

  @Test(.dependencies) func settingsChangedRecomputesResolvedKeybindings() async {
    var settings = GlobalSettings.default
    settings.keybindingUserOverrides = KeybindingUserOverrideStore(
      overrides: [
        AppShortcuts.CommandID.openSettings: KeybindingUserOverride(
          binding: Keybinding(key: ";", modifiers: .init(command: true))
        ),
      ]
    )

    let expectedResolved = KeybindingResolver.resolve(
      schema: .appResolverSchema(),
      userOverrides: settings.keybindingUserOverrides
    )

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.settings(.delegate(.settingsChanged(settings)))) {
      $0.settings.keybindingUserOverrides = settings.keybindingUserOverrides
      $0.resolvedKeybindings = expectedResolved
    }
    await store.receive(\.repositories.setGithubIntegrationEnabled)
    await store.receive(\.repositories.setAutomaticallyArchiveMergedWorktrees)
    await store.receive(\.repositories.setMoveNotifiedWorktreeToTop)
    await store.receive(\.updates.applySettings) {
      $0.updates.didConfigureUpdates = true
    }
    await store.receive(\.repositories.refreshGithubIntegrationAvailability) {
      $0.repositories.githubIntegrationAvailability = .checking
    }
    await store.receive(\.repositories.githubIntegrationAvailabilityUpdated) {
      $0.repositories.githubIntegrationAvailability = .available
      $0.repositories.queuedPullRequestRefreshByRepositoryID = [:]
      $0.repositories.inFlightPullRequestRefreshRepositoryIDs = []
    }

    expectNoDifference(
      store.state.resolvedKeybindings.display(for: AppShortcuts.CommandID.openSettings),
      "⌘;"
    )
  }

  @Test(.dependencies) func clearTerminalLayoutSnapshotShowsSuccessToast() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.settings(.delegate(.terminalLayoutSnapshotCleared(success: true))))
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .success("Saved terminal layout cleared")
    }
  }
}
