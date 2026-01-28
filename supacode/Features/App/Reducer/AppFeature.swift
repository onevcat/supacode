import AppKit
import ComposableArchitecture
import Foundation
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
    var selectedRunScript: String = ""
    var runScriptStatusByWorktreeID: [Worktree.ID: Bool] = [:]
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
    case worktreeSettingsLoaded(RepositorySettings, worktreeID: Worktree.ID)
    case openSelectedWorktree
    case openWorktree(OpenWorktreeAction)
    case openWorktreeFailed(OpenActionError)
    case newTerminal
    case runScript
    case stopRunScript
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
          state.selectedRunScript = ""
          return .merge(
            .send(.worktreeInfo(.worktreeChanged(nil, cachedPullRequest: nil))),
            .run { _ in
              await terminalClient.send(.setSelectedWorktreeID(nil))
            },
            .run { _ in
              await worktreeInfoWatcher.send(.setSelectedWorktreeID(nil))
            }
          )
        }
        let cachedPullRequest = state.repositories.worktreeInfoByID[worktree.id]?.pullRequest
        let rootURL = worktree.repositoryRootURL
        let worktreeID = worktree.id
        let repositorySettingsClient = repositorySettingsClient
        return .merge(
          .send(.worktreeInfo(.worktreeChanged(worktree, cachedPullRequest: cachedPullRequest))),
          .run { _ in
            await terminalClient.send(.setSelectedWorktreeID(worktree.id))
            await terminalClient.send(.clearNotificationIndicator(worktree))
          },
          .run { _ in
            await worktreeInfoWatcher.send(.setSelectedWorktreeID(worktree.id))
          },
          .run { send in
            let settings = repositorySettingsClient.load(rootURL)
            await send(.worktreeSettingsLoaded(settings, worktreeID: worktreeID))
          }
        )

      case .repositories(.delegate(.repositoriesChanged(let repositories))):
        let ids = Set(repositories.flatMap { $0.worktrees.map(\.id) })
        let worktrees = repositories.flatMap(\.worktrees)
        state.runScriptStatusByWorktreeID = state.runScriptStatusByWorktreeID.filter { ids.contains($0.key) }
        if case .repository(let repositoryID) = state.settings.selection,
           !repositories.contains(where: { $0.id == repositoryID })
        {
          return .merge(
            .send(.settings(.setSelection(.general))),
            .run { _ in
              await terminalClient.send(.prune(ids))
            },
            .run { _ in
              await worktreeInfoWatcher.send(.setWorktrees(worktrees))
            }
          )
        }
        return .merge(
          .run { _ in
            await terminalClient.send(.prune(ids))
          },
          .run { _ in
            await worktreeInfoWatcher.send(.setWorktrees(worktrees))
          }
        )

      case .repositories(.delegate(.openRepositorySettings(let repositoryID))):
        guard state.repositories.repositories.contains(where: { $0.id == repositoryID }) else {
          return .none
        }
        let selection = SettingsSection.repository(repositoryID)
        return .merge(
          .send(.settings(.setSelection(selection))),
          .run { _ in
            await MainActor.run {
              SettingsWindowManager.shared.show()
            }
          }
        )

      case .settings(.setSelection(let selection)):
        switch selection {
        case .repository(let repositoryID):
          guard let repository = state.repositories.repositories.first(where: { $0.id == repositoryID }) else {
            state.settings.repositorySettings = nil
            return .none
          }
          let settings = repositorySettingsClient.load(repository.rootURL)
          state.settings.repositorySettings = RepositorySettingsFeature.State(
            rootURL: repository.rootURL,
            settings: settings
          )
        case .general, .notifications, .updates, .github:
          state.settings.repositorySettings = nil
        }
        return .none

      case .repositories(.worktreePullRequestLoaded(let worktreeID, let pullRequest)):
        return .send(.worktreeInfo(.cachedPullRequestUpdated(worktreeID, pullRequest)))

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
        let rootURL = worktree.repositoryRootURL
        let actionID = action.settingsID
        let repositorySettingsClient = repositorySettingsClient
        return .run { _ in
          var settings = repositorySettingsClient.load(rootURL)
          settings.openActionID = actionID
          repositorySettingsClient.save(settings, rootURL)
        }

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
        let shouldRunSetupScript = state.repositories.pendingSetupScriptWorktreeIDs.contains(worktree.id)
        var effects: [Effect<Action>] = [
          .run { _ in
            await terminalClient.send(.createTab(worktree, runSetupScriptIfNew: shouldRunSetupScript))
          },
        ]
        if shouldRunSetupScript {
          effects.append(.send(.repositories(.consumeSetupScript(worktree.id))))
        }
        return .merge(effects)

      case .runScript:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        let rootURL = worktree.repositoryRootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { _ in
          let settings = repositorySettingsClient.load(rootURL)
          let trimmed = settings.runScript.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          await terminalClient.send(.runScript(worktree, script: settings.runScript))
        }

      case .stopRunScript:
        guard let worktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID) else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.stopRunScript(worktree))
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

      case .settings(.repositorySettings(.delegate(.settingsChanged(let rootURL)))):
        guard let selectedWorktree = state.repositories.worktree(for: state.repositories.selectedWorktreeID),
              selectedWorktree.repositoryRootURL == rootURL
        else {
          return .none
        }
        let worktreeID = selectedWorktree.id
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          let settings = repositorySettingsClient.load(rootURL)
          await send(.worktreeSettingsLoaded(settings, worktreeID: worktreeID))
        }

      case .worktreeSettingsLoaded(let settings, let worktreeID):
        guard state.repositories.selectedWorktreeID == worktreeID else {
          return .none
        }
        state.openActionSelection = OpenWorktreeAction.fromSettingsID(settings.openActionID)
        state.selectedRunScript = settings.runScript
        return .none

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

      case .terminalEvent(.runScriptStatusChanged(let worktreeID, let isRunning)):
        if isRunning {
          state.runScriptStatusByWorktreeID[worktreeID] = true
        } else {
          state.runScriptStatusByWorktreeID.removeValue(forKey: worktreeID)
        }
        return .none

      case .terminalEvent:
        return .none
      }
    }
    core
      .printActionLabels()
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
    #if !DEBUG
    SentrySDK.logger.info("received action: \(actionLabel)")
    #endif
    return base.reduce(into: &state, action: action)
  }
}

private extension Reducer {
  func printActionLabels() -> ActionLabelReducer<Self> {
    ActionLabelReducer(base: self)
  }
}
