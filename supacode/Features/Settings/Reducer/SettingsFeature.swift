import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var appearanceMode: AppearanceMode
    var confirmBeforeQuit: Bool
    var updatesAutomaticallyCheckForUpdates: Bool
    var updatesAutomaticallyDownloadUpdates: Bool
    var inAppNotificationsEnabled: Bool
    var notificationSoundEnabled: Bool
    var githubIntegrationEnabled: Bool
    var deleteBranchOnArchive: Bool
    var selection: SettingsSection = .general
    var repositorySettings: RepositorySettingsFeature.State?

    init(settings: GlobalSettings = .default) {
      appearanceMode = settings.appearanceMode
      confirmBeforeQuit = settings.confirmBeforeQuit
      updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
      updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
      inAppNotificationsEnabled = settings.inAppNotificationsEnabled
      notificationSoundEnabled = settings.notificationSoundEnabled
      githubIntegrationEnabled = settings.githubIntegrationEnabled
      deleteBranchOnArchive = settings.deleteBranchOnArchive
    }

    var globalSettings: GlobalSettings {
      GlobalSettings(
        appearanceMode: appearanceMode,
        confirmBeforeQuit: confirmBeforeQuit,
        updatesAutomaticallyCheckForUpdates: updatesAutomaticallyCheckForUpdates,
        updatesAutomaticallyDownloadUpdates: updatesAutomaticallyDownloadUpdates,
        inAppNotificationsEnabled: inAppNotificationsEnabled,
        notificationSoundEnabled: notificationSoundEnabled,
        githubIntegrationEnabled: githubIntegrationEnabled,
        deleteBranchOnArchive: deleteBranchOnArchive
      )
    }
  }

  enum Action {
    case task
    case settingsLoaded(GlobalSettings)
    case setAppearanceMode(AppearanceMode)
    case setConfirmBeforeQuit(Bool)
    case setUpdatesAutomaticallyCheckForUpdates(Bool)
    case setUpdatesAutomaticallyDownloadUpdates(Bool)
    case setInAppNotificationsEnabled(Bool)
    case setNotificationSoundEnabled(Bool)
    case setGithubIntegrationEnabled(Bool)
    case setDeleteBranchOnArchive(Bool)
    case setSelection(SettingsSection)
    case repositorySettings(RepositorySettingsFeature.Action)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(GlobalSettings)
  }

  @Dependency(\.settingsClient) private var settingsClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          let settings = await settingsClient.load()
          await send(.settingsLoaded(settings))
        }

      case .settingsLoaded(let settings):
        state.appearanceMode = settings.appearanceMode
        state.confirmBeforeQuit = settings.confirmBeforeQuit
        state.updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
        state.updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
        state.inAppNotificationsEnabled = settings.inAppNotificationsEnabled
        state.notificationSoundEnabled = settings.notificationSoundEnabled
        state.githubIntegrationEnabled = settings.githubIntegrationEnabled
        state.deleteBranchOnArchive = settings.deleteBranchOnArchive
        return .send(.delegate(.settingsChanged(settings)))

      case .setAppearanceMode(let mode):
        state.appearanceMode = mode
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setConfirmBeforeQuit(let value):
        state.confirmBeforeQuit = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setUpdatesAutomaticallyCheckForUpdates(let value):
        state.updatesAutomaticallyCheckForUpdates = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setUpdatesAutomaticallyDownloadUpdates(let value):
        state.updatesAutomaticallyDownloadUpdates = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setInAppNotificationsEnabled(let value):
        state.inAppNotificationsEnabled = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setNotificationSoundEnabled(let value):
        state.notificationSoundEnabled = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setDeleteBranchOnArchive(let value):
        state.deleteBranchOnArchive = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setGithubIntegrationEnabled(let value):
        state.githubIntegrationEnabled = value
        let settings = state.globalSettings
        return .merge(
          .send(.delegate(.settingsChanged(settings))),
          .run { _ in
            await settingsClient.save(settings)
          }
        )

      case .setSelection(let selection):
        state.selection = selection
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
