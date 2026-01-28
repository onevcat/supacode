import ComposableArchitecture
import Foundation

@Reducer
struct RepositorySettingsFeature {
  @ObservableState
  struct State: Equatable {
    var rootURL: URL
    var settings: RepositorySettings

    init(rootURL: URL, settings: RepositorySettings = .default) {
      self.rootURL = rootURL
      self.settings = settings
    }
  }

  enum Action: Equatable {
    case task
    case settingsLoaded(RepositorySettings)
    case setSetupScript(String)
    case setRunScript(String)
  }

  @Dependency(\.repositorySettingsClient) private var repositorySettingsClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        let rootURL = state.rootURL
        return .run { send in
          let settings = await repositorySettingsClient.load(rootURL)
          await send(.settingsLoaded(settings))
        }

      case .settingsLoaded(let settings):
        state.settings = settings
        return .none

      case .setSetupScript(let script):
        state.settings.setupScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        return .run { _ in
          await repositorySettingsClient.save(settings, rootURL)
          await MainActor.run {
            NotificationCenter.default.post(
              name: Notification.Name("repositorySettingsChanged"),
              object: rootURL
            )
          }
        }

      case .setRunScript(let script):
        state.settings.runScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        return .run { _ in
          await repositorySettingsClient.save(settings, rootURL)
          await MainActor.run {
            NotificationCenter.default.post(
              name: Notification.Name("repositorySettingsChanged"),
              object: rootURL
            )
          }
        }
      }
    }
  }
}
