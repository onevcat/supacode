import Carbon.HIToolbox
import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct SettingsFeatureTests {
  @Test(.dependencies) func loadSettings() async {
    let loaded = GlobalSettings(
      appearanceMode: .dark,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: true,
      updateChannel: .stable,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: true,
      systemNotificationsEnabled: true,
      moveNotifiedWorktreeToTop: false,
      analyticsEnabled: false,
      crashReportsEnabled: true,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: false,
      automaticallyArchiveMergedWorktrees: true,
      promptForWorktreeCreation: true,
      terminalThemeSyncEnabled: false,
    )
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = loaded }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.appearanceMode = .dark
      $0.defaultEditorID = OpenWorktreeAction.automaticSettingsID
      $0.confirmBeforeQuit = true
      $0.updateChannel = .stable
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.notificationSoundEnabled = true
      $0.moveNotifiedWorktreeToTop = false
      $0.systemNotificationsEnabled = true
      $0.analyticsEnabled = false
      $0.crashReportsEnabled = true
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnDeleteWorktree = false
      $0.automaticallyArchiveMergedWorktrees = true
      $0.promptForWorktreeCreation = true
      $0.fetchOriginBeforeWorktreeCreation = true
      $0.terminalThemeSyncEnabled = false
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func savesUpdatesChanges() async {
    let initialSettings = GlobalSettings(
      appearanceMode: .system,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: true,
      updateChannel: .stable,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: false,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: false,
      systemNotificationsEnabled: false,
      moveNotifiedWorktreeToTop: true,
      analyticsEnabled: true,
      crashReportsEnabled: false,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: true,
      automaticallyArchiveMergedWorktrees: false,
      promptForWorktreeCreation: false
    )
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.appearanceMode, .light))) {
      $0.appearanceMode = .light
    }
    let expectedSettings = GlobalSettings(
      appearanceMode: .light,
      defaultEditorID: initialSettings.defaultEditorID,
      confirmBeforeQuit: initialSettings.confirmBeforeQuit,
      updateChannel: initialSettings.updateChannel,
      updatesAutomaticallyCheckForUpdates: initialSettings.updatesAutomaticallyCheckForUpdates,
      updatesAutomaticallyDownloadUpdates: initialSettings.updatesAutomaticallyDownloadUpdates,
      inAppNotificationsEnabled: initialSettings.inAppNotificationsEnabled,
      notificationSoundEnabled: initialSettings.notificationSoundEnabled,
      systemNotificationsEnabled: initialSettings.systemNotificationsEnabled,
      moveNotifiedWorktreeToTop: initialSettings.moveNotifiedWorktreeToTop,
      analyticsEnabled: initialSettings.analyticsEnabled,
      crashReportsEnabled: initialSettings.crashReportsEnabled,
      githubIntegrationEnabled: initialSettings.githubIntegrationEnabled,
      deleteBranchOnDeleteWorktree: initialSettings.deleteBranchOnDeleteWorktree,
      automaticallyArchiveMergedWorktrees: initialSettings.automaticallyArchiveMergedWorktrees,
      promptForWorktreeCreation: initialSettings.promptForWorktreeCreation
    )
    await store.receive(\.delegate.settingsChanged)

    expectNoDifference(settingsFile.global, expectedSettings)
  }

  @Test(.dependencies) func setSystemNotificationsEnabledPersistsChanges() async {
    var initialSettings = GlobalSettings.default
    initialSettings.systemNotificationsEnabled = false
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.setSystemNotificationsEnabled(true)) {
      $0.systemNotificationsEnabled = true
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.systemNotificationsEnabled == true)
  }

  @Test(.dependencies) func selectionDoesNotMutateRepositorySettings() async {
    let selection = SettingsSection.repository("repo-id")
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.setSelection(selection)) {
      $0.selection = selection
    }

    await store.send(.setSelection(.general)) {
      $0.selection = .general
    }
  }

  @Test(.dependencies) func setSelectionNilClosesSettingsWindow() async {
    var state = SettingsFeature.State()
    state.selection = .general
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    await store.send(.setSelection(nil)) {
      $0.selection = nil
    }
  }

  @Test(.dependencies) func loadingSettingsDoesNotResetSelection() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let selection = SettingsSection.repository("repo-id")
    var state = SettingsFeature.State()
    state.selection = selection
    state.repositorySettings = RepositorySettingsFeature.State(
      rootURL: rootURL,
      settings: .default
    )
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    let loaded = GlobalSettings(
      appearanceMode: .light,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: false,
      updateChannel: .tip,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: false,
      systemNotificationsEnabled: true,
      moveNotifiedWorktreeToTop: true,
      analyticsEnabled: true,
      crashReportsEnabled: false,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: true,
      automaticallyArchiveMergedWorktrees: true,
      promptForWorktreeCreation: false
    )

    await store.send(.settingsLoaded(loaded)) {
      $0.appearanceMode = .light
      $0.defaultEditorID = OpenWorktreeAction.automaticSettingsID
      $0.confirmBeforeQuit = false
      $0.updateChannel = .tip
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.notificationSoundEnabled = false
      $0.moveNotifiedWorktreeToTop = true
      $0.systemNotificationsEnabled = true
      $0.analyticsEnabled = true
      $0.crashReportsEnabled = false
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnDeleteWorktree = true
      $0.automaticallyArchiveMergedWorktrees = true
      $0.promptForWorktreeCreation = false
      $0.selection = selection
      $0.repositorySettings = RepositorySettingsFeature.State(
        rootURL: rootURL,
        settings: .default
      )
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func settingsLoadedNormalizesDefaultWorktreeBaseDirectoryPath() async {
    var loaded = GlobalSettings.default
    loaded.defaultWorktreeBaseDirectoryPath = " ~/worktrees "
    let expectedPath = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "worktrees", directoryHint: .isDirectory)
      .standardizedFileURL
      .path(percentEncoded: false)
    let storage = SettingsTestStorage()
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json")
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
    }

    await store.send(.settingsLoaded(loaded)) {
      $0.defaultWorktreeBaseDirectoryPath = expectedPath
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(store.state.defaultWorktreeBaseDirectoryPath == expectedPath)
  }

  @Test(.dependencies) func changingDefaultWorktreeBaseDirectoryUpdatesRepositorySettingsState() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let expectedPath = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "worktrees", directoryHint: .isDirectory)
      .standardizedFileURL
      .path(percentEncoded: false)
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = .default }
    var state = SettingsFeature.State()
    state.repositorySettings = RepositorySettingsFeature.State(
      rootURL: rootURL,
      settings: .default
    )
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.defaultWorktreeBaseDirectoryPath, " ~/worktrees "))) {
      $0.defaultWorktreeBaseDirectoryPath = " ~/worktrees "
      $0.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath = expectedPath
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(store.state.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath == expectedPath)
    #expect(settingsFile.global.defaultWorktreeBaseDirectoryPath == expectedPath)
  }

  // MARK: - Sorted repositories.

  @Test(.dependencies) func repositoriesChangedSortsByNameCaseInsensitive() async {
    let repoC = Repository(
      id: "/tmp/charlie",
      rootURL: URL(fileURLWithPath: "/tmp/charlie"),
      name: "Charlie",
      worktrees: [],
    )
    let repoA = Repository(
      id: "/tmp/alpha",
      rootURL: URL(fileURLWithPath: "/tmp/alpha"),
      name: "alpha",
      worktrees: [],
    )
    let repoB = Repository(
      id: "/tmp/bravo",
      rootURL: URL(fileURLWithPath: "/tmp/bravo"),
      name: "Bravo",
      worktrees: [],
    )

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.repositoriesChanged([repoC, repoA, repoB])) {
      $0.sortedRepositoryIDs = [repoA.id, repoB.id, repoC.id]
    }
  }

  // MARK: - Keyboard shortcut overrides.

  @Test(.dependencies) func updateShortcutPersistsOverride() async {
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = .default }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command])
    await store.send(.updateShortcut(id: .newWorktree, override: override)) {
      $0.shortcutOverrides[.newWorktree] = override
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == override)
  }

  @Test(.dependencies) func updateShortcutRemovesOverride() async {
    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command])
    var initialSettings = GlobalSettings.default
    initialSettings.shortcutOverrides = [.newWorktree: override]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.updateShortcut(id: .newWorktree, override: nil)) {
      $0.shortcutOverrides.removeValue(forKey: .newWorktree)
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == nil)
  }

  @Test(.dependencies) func resetAllShortcutsClearsOverrides() async {
    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command])
    var initialSettings = GlobalSettings.default
    initialSettings.shortcutOverrides = [
      .newWorktree: override,
      .openSettings: override,
    ]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.resetAllShortcuts) {
      $0.shortcutOverrides = [:]
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides.isEmpty)
  }

  // MARK: - Toggle shortcut enabled.

  @Test(.dependencies) func toggleShortcutDisabledInsertsDisabledSentinel() async {
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = .default }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.toggleShortcutEnabled(id: .newWorktree, enabled: false)) {
      $0.shortcutOverrides[.newWorktree] = .disabled
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == .disabled)
  }

  @Test(.dependencies) func toggleShortcutDisabledWithExistingOverrideFlipsFlag() async {
    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command])
    var initialSettings = GlobalSettings.default
    initialSettings.shortcutOverrides = [.newWorktree: override]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    let expected = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command], isEnabled: false)
    await store.send(.toggleShortcutEnabled(id: .newWorktree, enabled: false)) {
      $0.shortcutOverrides[.newWorktree] = expected
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == expected)
  }

  @Test(.dependencies) func toggleShortcutEnabledRemovesDisabledSentinel() async {
    var initialSettings = GlobalSettings.default
    initialSettings.shortcutOverrides = [.newWorktree: .disabled]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.toggleShortcutEnabled(id: .newWorktree, enabled: true)) {
      $0.shortcutOverrides.removeValue(forKey: .newWorktree)
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == nil)
  }

  @Test(.dependencies) func toggleShortcutEnabledReEnablesCustomOverride() async {
    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command], isEnabled: false)
    var initialSettings = GlobalSettings.default
    initialSettings.shortcutOverrides = [.newWorktree: override]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    let expected = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command], isEnabled: true)
    await store.send(.toggleShortcutEnabled(id: .newWorktree, enabled: true)) {
      $0.shortcutOverrides[.newWorktree] = expected
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.shortcutOverrides[.newWorktree] == expected)
  }

  // MARK: - Settings loaded includes overrides.

  @Test(.dependencies) func settingsLoadedIncludesShortcutOverrides() async {
    let override = AppShortcutOverride(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command])
    var loaded = GlobalSettings.default
    loaded.shortcutOverrides = [.openSettings: override]
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = loaded }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.shortcutOverrides = [.openSettings: override]
    }
    await store.receive(\.delegate.settingsChanged)
  }
}
