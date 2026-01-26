import ComposableArchitecture
import Testing

@testable import supacode

@MainActor
struct SettingsFeatureTests {
  @Test func loadSettings() async {
    let loaded = GlobalSettings(
      appearanceMode: .dark,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: true
    )
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsClient.load = { loaded }
    }

    await store.send(.task) {
      $0.appearanceMode = .dark
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.notificationSoundEnabled = true
    }
    await store.receive(.delegate(.settingsChanged(loaded)))
  }

  @Test func savesUpdatesChanges() async {
    let saved = LockIsolated<GlobalSettings?>(nil)
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsClient.save = { settings in
        saved.withValue { $0 = settings }
      }
    }

    await store.send(.setAppearanceMode(.dark)) {
      $0.appearanceMode = .dark
    }
    await store.receive(.delegate(.settingsChanged(GlobalSettings(
      appearanceMode: .dark,
      updatesAutomaticallyCheckForUpdates: true,
      updatesAutomaticallyDownloadUpdates: false,
      inAppNotificationsEnabled: true,
      notificationSoundEnabled: true
    ))))

    #expect(saved.value == GlobalSettings(
      appearanceMode: .dark,
      updatesAutomaticallyCheckForUpdates: true,
      updatesAutomaticallyDownloadUpdates: false,
      inAppNotificationsEnabled: true,
      notificationSoundEnabled: true
    ))
  }
}
