import ComposableArchitecture
import Foundation

@Reducer
struct RepositorySettingsFeature {
  @ObservableState
  struct State: Equatable {
    var rootURL: URL
    var settings: RepositorySettings

    init(rootURL: URL, settings: RepositorySettings) {
      self.rootURL = rootURL
      self.settings = settings
    }
  }

  enum Action: Equatable {
    case task
    case settingsLoaded(RepositorySettings)
    case setSetupScript(String)
    case setRunScript(String)
    case setCopyIgnoredOnWorktreeCreate(Bool)
    case setCopyUntrackedOnWorktreeCreate(Bool)
    case delegate(Delegate)
  }

  enum Delegate: Equatable {
    case settingsChanged(URL)
  }

  @Dependency(\.repositorySettingsClient) private var repositorySettingsClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          let settings = repositorySettingsClient.load(rootURL)
          await send(.settingsLoaded(settings))
        }

      case .settingsLoaded(let settings):
        state.settings = settings
        return .none

      case .setSetupScript(let script):
        state.settings.setupScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setRunScript(let script):
        state.settings.runScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setCopyIgnoredOnWorktreeCreate(let isEnabled):
        state.settings.copyIgnoredOnWorktreeCreate = isEnabled
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setCopyUntrackedOnWorktreeCreate(let isEnabled):
        state.settings.copyUntrackedOnWorktreeCreate = isEnabled
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .delegate:
        return .none
      }
    }
  }
}
