import ComposableArchitecture
import Foundation
import PostHog

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var appearanceMode: AppearanceMode
    var confirmBeforeQuit: Bool
    var updatesAutomaticallyCheckForUpdates: Bool
    var updatesAutomaticallyDownloadUpdates: Bool
    var inAppNotificationsEnabled: Bool
    var dockBadgeEnabled: Bool
    var notificationSoundEnabled: Bool
    var githubIntegrationEnabled: Bool
    var deleteBranchOnArchive: Bool
    var sortMergedWorktreesToBottom: Bool
    var selection: SettingsSection? = .general
    var repositorySettings: RepositorySettingsFeature.State?

    init(settings: GlobalSettings = .default) {
      appearanceMode = settings.appearanceMode
      confirmBeforeQuit = settings.confirmBeforeQuit
      updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
      updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
      inAppNotificationsEnabled = settings.inAppNotificationsEnabled
      dockBadgeEnabled = settings.dockBadgeEnabled
      notificationSoundEnabled = settings.notificationSoundEnabled
      githubIntegrationEnabled = settings.githubIntegrationEnabled
      deleteBranchOnArchive = settings.deleteBranchOnArchive
      sortMergedWorktreesToBottom = settings.sortMergedWorktreesToBottom
    }

    var globalSettings: GlobalSettings {
      GlobalSettings(
        appearanceMode: appearanceMode,
        confirmBeforeQuit: confirmBeforeQuit,
        updatesAutomaticallyCheckForUpdates: updatesAutomaticallyCheckForUpdates,
        updatesAutomaticallyDownloadUpdates: updatesAutomaticallyDownloadUpdates,
        inAppNotificationsEnabled: inAppNotificationsEnabled,
        dockBadgeEnabled: dockBadgeEnabled,
        notificationSoundEnabled: notificationSoundEnabled,
        githubIntegrationEnabled: githubIntegrationEnabled,
        deleteBranchOnArchive: deleteBranchOnArchive,
        sortMergedWorktreesToBottom: sortMergedWorktreesToBottom
      )
    }
  }

  enum Action: BindableAction {
    case task
    case settingsLoaded(GlobalSettings)
    case setSelection(SettingsSection?)
    case repositorySettings(RepositorySettingsFeature.Action)
    case delegate(Delegate)
    case binding(BindingAction<State>)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(GlobalSettings)
  }

  @Dependency(\.analyticsClient) private var analyticsClient

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        @Shared(.settingsFile) var settingsFile
        return .send(.settingsLoaded(settingsFile.global))

      case .settingsLoaded(let settings):
        state.appearanceMode = settings.appearanceMode
        state.confirmBeforeQuit = settings.confirmBeforeQuit
        state.updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
        state.updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
        state.inAppNotificationsEnabled = settings.inAppNotificationsEnabled
        state.dockBadgeEnabled = settings.dockBadgeEnabled
        state.notificationSoundEnabled = settings.notificationSoundEnabled
        state.githubIntegrationEnabled = settings.githubIntegrationEnabled
        state.deleteBranchOnArchive = settings.deleteBranchOnArchive
        state.sortMergedWorktreesToBottom = settings.sortMergedWorktreesToBottom
        return .send(.delegate(.settingsChanged(settings)))

      case .binding:
        analyticsClient.capture("settings_changed", nil)
        let settings = state.globalSettings
        @Shared(.settingsFile) var settingsFile
        $settingsFile.withLock { $0.global = settings }
        return .send(.delegate(.settingsChanged(settings)))

      case .setSelection(let selection):
        state.selection = selection ?? .general
        return .none

      case .repositorySettings:
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.repositorySettings, action: \.repositorySettings) {
      RepositorySettingsFeature()
    }
  }
}
