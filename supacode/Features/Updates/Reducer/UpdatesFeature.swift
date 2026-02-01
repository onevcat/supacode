import ComposableArchitecture

@Reducer
struct UpdatesFeature {
  @ObservableState
  struct State: Equatable {
    var didConfigureUpdates = false
  }

  enum Action {
    case applySettings(
      automaticallyChecks: Bool,
      automaticallyDownloads: Bool
    )
    case checkForUpdates
  }

  @Dependency(\.updaterClient) private var updaterClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .applySettings(let checks, let downloads):
        let checkInBackground = !state.didConfigureUpdates
        state.didConfigureUpdates = true
        return .run { _ in
          await updaterClient.configure(checks, downloads, checkInBackground)
        }

      case .checkForUpdates:
        return .run { _ in
          await updaterClient.checkForUpdates()
        }
      }
    }
  }
}
