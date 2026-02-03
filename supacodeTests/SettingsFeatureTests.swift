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
      confirmBeforeQuit: true,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      dockBadgeEnabled: false,
      notificationSoundEnabled: true,
      githubIntegrationEnabled: true,
      deleteBranchOnArchive: false,
      sortMergedWorktreesToBottom: true
    )
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = loaded }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.appearanceMode = .dark
      $0.confirmBeforeQuit = true
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.dockBadgeEnabled = false
      $0.notificationSoundEnabled = true
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnArchive = false
      $0.sortMergedWorktreesToBottom = true
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func savesUpdatesChanges() async {
    let initialSettings = GlobalSettings(
      appearanceMode: .system,
      confirmBeforeQuit: true,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: false,
      inAppNotificationsEnabled: false,
      dockBadgeEnabled: true,
      notificationSoundEnabled: false,
      githubIntegrationEnabled: true,
      deleteBranchOnArchive: true,
      sortMergedWorktreesToBottom: false
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
      confirmBeforeQuit: initialSettings.confirmBeforeQuit,
      updatesAutomaticallyCheckForUpdates: initialSettings.updatesAutomaticallyCheckForUpdates,
      updatesAutomaticallyDownloadUpdates: initialSettings.updatesAutomaticallyDownloadUpdates,
      inAppNotificationsEnabled: initialSettings.inAppNotificationsEnabled,
      dockBadgeEnabled: initialSettings.dockBadgeEnabled,
      notificationSoundEnabled: initialSettings.notificationSoundEnabled,
      githubIntegrationEnabled: initialSettings.githubIntegrationEnabled,
      deleteBranchOnArchive: initialSettings.deleteBranchOnArchive,
      sortMergedWorktreesToBottom: initialSettings.sortMergedWorktreesToBottom
    )
    await store.receive(\.delegate.settingsChanged)

    expectNoDifference(settingsFile.global, expectedSettings)
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
      confirmBeforeQuit: false,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      dockBadgeEnabled: false,
      notificationSoundEnabled: false,
      githubIntegrationEnabled: true,
      deleteBranchOnArchive: true,
      sortMergedWorktreesToBottom: true
    )

    await store.send(.settingsLoaded(loaded)) {
      $0.appearanceMode = .light
      $0.confirmBeforeQuit = false
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.dockBadgeEnabled = false
      $0.notificationSoundEnabled = false
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnArchive = true
      $0.sortMergedWorktreesToBottom = true
      $0.selection = selection
      $0.repositorySettings = RepositorySettingsFeature.State(
        rootURL: rootURL,
        settings: .default
      )
    }
    await store.receive(\.delegate.settingsChanged)
  }
}
