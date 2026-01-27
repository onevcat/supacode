import AppKit
import ComposableArchitecture
import Sentry
import SwiftUI

private let notificationSound: NSSound? = {
  guard let url = Bundle.main.url(forResource: "notification", withExtension: "wav") else {
    return nil
  }
  return NSSound(contentsOf: url, byReference: true)
}()

@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var repositories: RepositoriesFeature.State
    var worktreeInfo = WorktreeInfoFeature.State()
    var settings: SettingsFeature.State
    var updates = UpdatesFeature.State()
    var openActionSelection: OpenWorktreeAction = .finder
    @Presents var alert: AlertState<Alert>?

    init(
      repositories: RepositoriesFeature.State = .init(),
      settings: SettingsFeature.State = .init()
    ) {
      self.repositories = repositories
      self.settings = settings
    }
  }

  enum Action: Equatable {
    case task
    case scenePhaseChanged(ScenePhase)
    case repositories(RepositoriesFeature.Action)
    case worktreeInfo(WorktreeInfoFeature.Action)
    case settings(SettingsFeature.Action)
    case updates(UpdatesFeature.Action)
    case openActionSelectionChanged(OpenWorktreeAction)
    case openSelectedWorktree
    case openWorktree(OpenWorktreeAction)
    case openWorktreeFailed(OpenActionError)
    case newTerminal
    case closeTab
    case closeSurface
    case startSearch
    case searchSelection
    case navigateSearchNext
    case navigateSearchPrevious
    case endSearch
    case alert(PresentationAction<Alert>)
    case terminalEvent(TerminalClient.Event)
  }

  enum Alert: Equatable {
    case dismiss
  }

  @Dependency(\.repositorySettingsClient) private var repositorySettingsClient
  @Dependency(\.workspaceClient) private var workspaceClient
  @Dependency(\.terminalClient) private var terminalClient
  @Dependency(\.worktreeInfoWatcher) private var worktreeInfoWatcher

  var body: some Reducer<State, Action> {
    let core = Reduce<State, Action> { state, action in
      switch action {
      case .task:
        return .merge(
          .send(.repositories(.task)),
          .send(.settings(.task)),
          .send(.worktreeInfo(.task)),
          .run { send in
            for await event in await terminalClient.events() {
              await send(.terminalEvent(event))
            }
          },
          .run { send in
            for await event in await worktreeInfoWatcher.events() {
              await send(.repositories(.worktreeInfoEvent(event)))
            }
          }
        )

      case .scenePhaseChanged(let phase):
        switch phase {
        case .active:
          return .merge(
            .send(.repositories(.loadPersistedRepositories)),
            .send(.worktreeInfo(.appBecameActive))
          )
        default:
          return .none
        }

      case .repositories(.delegate(.selectedWorktreeChanged(let worktree))):
        guard let worktree else {
          state.openActionSelection = .finder
          return .merge(
            .send(.worktreeInfo(.worktreeChanged(nil))),
            .run { _ in
              await terminalClient.send(.setSelectedWorktreeID(nil))
            },
            .run { _ in
              await worktreeInfoWatcher.send(.setSelectedWorktreeID(nil))
            }
          )
        }
        let settings = repositorySettingsClient.load(worktree.repositoryRootURL)
        state.openActionSelection = OpenWorktreeAction.fromSettingsID(settings.openActionID)
        return .merge(
          .send(.worktreeInfo(.worktreeChanged(worktree))),
          .run { _ in
            await terminalClient.send(.setSelectedWorktreeID(worktree.id))
            await terminalClient.send(.clearNotificationIndicator(worktree))
          },
          .run { _ in
            await worktreeInfoWatcher.send(.setSelectedWorktreeID(worktree.id))
          }
        )

      case .repositories(.delegate(.repositoriesChanged(let repositories))):
        let ids = Set(repositories.flatMap { $0.worktrees.map(\.id) })
        let worktrees = repositories.flatMap(\.worktrees)
        return .merge(
          .run { _ in
            await terminalClient.send(.prune(ids))
          },
          .run { _ in
            await worktreeInfoWatcher.send(.setWorktrees(worktrees))
          }
        )

      case .settings(.delegate(.settingsChanged(let settings))):
        return .merge(
          .send(
            .updates(
              .applySettings(
                automaticallyChecks: settings.updatesAutomaticallyCheckForUpdates,
                automaticallyDownloads: settings.updatesAutomaticallyDownloadUpdates
              )
            )
          ),
          .run { _ in
            await terminalClient.send(.setNotificationsEnabled(settings.inAppNotificationsEnabled))
          }
        )

      case .openActionSelectionChanged(let action):
        state.openActionSelection = action
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        var settings = repositorySettingsClient.load(worktree.repositoryRootURL)
        settings.openActionID = action.settingsID
        repositorySettingsClient.save(settings, worktree.repositoryRootURL)
        return .none

      case .openSelectedWorktree:
        return .send(.openWorktree(OpenWorktreeAction.availableSelection(state.openActionSelection)))

      case .openWorktree(let action):
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { send in
          await workspaceClient.open(action, worktree) { error in
            send(.openWorktreeFailed(error))
          }
        }

      case .openWorktreeFailed(let error):
        state.alert = AlertState {
          TextState(error.title)
        } actions: {
          ButtonState(role: .cancel, action: .dismiss) {
            TextState("OK")
          }
        } message: {
          TextState(error.message)
        }
        return .none

      case .newTerminal:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.createTab(worktree))
        }

      case .closeTab:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.closeFocusedTab(worktree))
        }

      case .closeSurface:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.closeFocusedSurface(worktree))
        }

      case .startSearch:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.startSearch(worktree))
        }

      case .searchSelection:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.searchSelection(worktree))
        }

      case .navigateSearchNext:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.navigateSearchNext(worktree))
        }

      case .navigateSearchPrevious:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.navigateSearchPrevious(worktree))
        }

      case .endSearch:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.endSearch(worktree))
        }

      case .alert(.dismiss):
        state.alert = nil
        return .none

      case .alert:
        return .none

      case .repositories:
        return .none

      case .worktreeInfo:
        return .none

      case .settings:
        return .none

      case .updates:
        return .none

      case .terminalEvent(.notificationReceived):
        guard state.settings.notificationSoundEnabled else { return .none }
        return .run { _ in
          await MainActor.run { _ = notificationSound?.play() }
        }

      case .terminalEvent:
        return .none
      }
    }
    core.printActionLabels()
    Scope(state: \.repositories, action: \.repositories) {
      RepositoriesFeature()
    }
    Scope(state: \.worktreeInfo, action: \.worktreeInfo) {
      WorktreeInfoFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Scope(state: \.updates, action: \.updates) {
      UpdatesFeature()
    }
  }
}

private struct ActionLabelReducer<Base: Reducer>: Reducer {
  let base: Base

  func reduce(into state: inout Base.State, action: Base.Action) -> Effect<Base.Action> {
    let actionLabel = debugCaseOutput(action)
    print("received action: \(actionLabel)")
    SentrySDK.logger.info("received action: \(actionLabel)")
    return base.reduce(into: &state, action: action)
  }
}

private extension Reducer {
  func printActionLabels() -> ActionLabelReducer<Self> {
    ActionLabelReducer(base: self)
  }
}
