import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var appearanceMode: AppearanceMode
    var updatesAutomaticallyCheckForUpdates: Bool
    var updatesAutomaticallyDownloadUpdates: Bool
    var inAppNotificationsEnabled: Bool
    var notificationSoundEnabled: Bool

    init(settings: GlobalSettings = .default) {
      appearanceMode = settings.appearanceMode
      updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
      updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
      inAppNotificationsEnabled = settings.inAppNotificationsEnabled
      notificationSoundEnabled = settings.notificationSoundEnabled
    }

    var globalSettings: GlobalSettings {
      GlobalSettings(
        appearanceMode: appearanceMode,
        updatesAutomaticallyCheckForUpdates: updatesAutomaticallyCheckForUpdates,
        updatesAutomaticallyDownloadUpdates: updatesAutomaticallyDownloadUpdates,
        inAppNotificationsEnabled: inAppNotificationsEnabled,
        notificationSoundEnabled: notificationSoundEnabled
      )
    }
  }

  enum Action: Equatable {
    case task
    case settingsLoaded(GlobalSettings)
    case setAppearanceMode(AppearanceMode)
    case setUpdatesAutomaticallyCheckForUpdates(Bool)
    case setUpdatesAutomaticallyDownloadUpdates(Bool)
    case setInAppNotificationsEnabled(Bool)
    case setNotificationSoundEnabled(Bool)
    case delegate(Delegate)
  }

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
        state = State(settings: settings)
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

      case .delegate:
        return .none
      }
    }
  }
}
