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
}
