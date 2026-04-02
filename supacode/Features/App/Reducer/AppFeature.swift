import AppKit
import ComposableArchitecture
import Foundation
import PostHog
import SwiftUI

private let appLogger = SupaLogger("App")

private enum CancelID {
  static let periodicRefresh = "app.periodicRefresh"
}

private func makeTerminalRestorableWorktrees(from repositories: [Repository]) -> [Worktree] {
  var worktrees: [Worktree] = []
  worktrees.reserveCapacity(repositories.reduce(0) { $0 + max(1, $1.worktrees.count) })
  for repository in repositories {
    if repository.capabilities.supportsWorktrees {
      worktrees.append(contentsOf: repository.worktrees)
      continue
    }
    if repository.capabilities.supportsRunnableFolderActions {
      worktrees.append(
        Worktree(
          id: repository.id,
          name: repository.name,
          detail: repository.rootURL.path(percentEncoded: false),
          workingDirectory: repository.rootURL,
          repositoryRootURL: repository.rootURL
        )
      )
    }
  }
  return worktrees
}

@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var repositories: RepositoriesFeature.State
    var settings: SettingsFeature.State
    var updates = UpdatesFeature.State()
    var commandPalette = CommandPaletteFeature.State()
    var openActionSelection: OpenWorktreeAction = .finder
    var selectedRunScript: String = ""
    var selectedCustomCommands: [UserCustomCommand] = []
    var resolvedKeybindings: ResolvedKeybindingMap = .appDefaults
    var runScriptDraft: String = ""
    var isRunScriptPromptPresented = false
    var runScriptStatusByWorktreeID: [Worktree.ID: Bool] = [:]
    var notificationIndicatorCount: Int = 0
    var lastKnownSystemNotificationsEnabled: Bool
    var launchRestoreMode: LaunchRestoreMode
    var suppressLayoutSaveUntilRelaunch = false
    @Presents var alert: AlertState<Alert>?

    init(
      repositories: RepositoriesFeature.State = .init(),
      settings: SettingsFeature.State = .init()
    ) {
      self.repositories = repositories
      self.settings = settings
      lastKnownSystemNotificationsEnabled = settings.systemNotificationsEnabled
      launchRestoreMode = settings.restoreTerminalLayoutOnLaunch ? .restoreLayout : .lastFocusedWorktree
    }
  }

  enum Action {
    case appLaunched
    case scenePhaseChanged(ScenePhase)
    case repositories(RepositoriesFeature.Action)
    case settings(SettingsFeature.Action)
    case updates(UpdatesFeature.Action)
    case commandPalette(CommandPaletteFeature.Action)
    case openActionSelectionChanged(OpenWorktreeAction)
    case worktreeSettingsLoaded(RepositorySettings, worktreeID: Worktree.ID)
    case worktreeUserSettingsLoaded(UserRepositorySettings, worktreeID: Worktree.ID)
    case openSelectedWorktree
    case openWorktree(OpenWorktreeAction)
    case openWorktreeFailed(OpenActionError)
    case requestQuit
    case newTerminal
    case runScript
    case runCustomCommand(Int)
    case runScriptDraftChanged(String)
    case runScriptPromptPresented(Bool)
    case saveRunScriptAndRun
    case stopRunScript
    case closeTab
    case closeSurface
    case startSearch
    case searchSelection
    case navigateSearchNext
    case navigateSearchPrevious
    case endSearch
    case systemNotificationsPermissionFailed(errorMessage: String?)
    case alert(PresentationAction<Alert>)
    case terminalEvent(TerminalClient.Event)
  }

  enum Alert: Equatable {
    case dismiss
    case confirmQuit
  }

  @Dependency(AnalyticsClient.self) private var analyticsClient
  @Dependency(RepositoryPersistenceClient.self) private var repositoryPersistence
  @Dependency(WorkspaceClient.self) private var workspaceClient
  @Dependency(SettingsWindowClient.self) private var settingsWindowClient
  @Dependency(NotificationSoundClient.self) private var notificationSoundClient
  @Dependency(SystemNotificationClient.self) private var systemNotificationClient
  @Dependency(TerminalClient.self) private var terminalClient
  @Dependency(WorktreeInfoWatcherClient.self) private var worktreeInfoWatcher
  @Dependency(CustomShortcutRegistryClient.self) private var customShortcutRegistryClient

  private func resolvedKeybindings(
    settings: SettingsFeature.State,
    customCommands: [UserCustomCommand]
  ) -> ResolvedKeybindingMap {
    let migration = LegacyCustomCommandShortcutMigration.migrate(commands: customCommands)
    var resolved = KeybindingResolver.resolve(
      schema: .appResolverSchema(customCommands: customCommands),
      userOverrides: settings.keybindingUserOverrides,
      migratedOverrides: migration.overrides
    )
    let customCommandIDs = customCommands.map { command in
      LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id)
    }
    let customCommandBindings = customCommandIDs.compactMap { resolved.keybinding(for: $0) }
    guard !customCommandBindings.isEmpty else {
      return resolved
    }
    for binding in AppShortcuts.bindings where binding.scope == .configurableAppAction {
      guard let resolvedBinding = resolved.binding(for: binding.id),
        let shortcut = resolvedBinding.binding,
        customCommandBindings.contains(shortcut)
      else {
        continue
      }
      resolved.bindingsByCommandID[binding.id] = ResolvedKeybinding(
        command: resolvedBinding.command,
        binding: nil,
        source: resolvedBinding.source
      )
    }
    return resolved
  }

  var body: some Reducer<State, Action> {
    let core = Reduce<State, Action> { state, action in
      switch action {
      case .appLaunched:
        try? SupacodePaths.migrateLegacyCacheFilesIfNeeded()
        appLogger.info("[LayoutRestore] appLaunched: launchRestoreMode=\(String(describing: state.launchRestoreMode))")
        state.repositories.launchRestoreMode = state.launchRestoreMode
        return .merge(
          .send(.repositories(.task)),
          .send(.settings(.task)),
          .run { _ in
            await MainActor.run {
              NSApplication.shared.dockTile.badgeLabel = nil
            }
          },
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
          analyticsClient.capture("app_activated", nil)
          return .merge(
            .send(.repositories(.refreshWorktrees)),
            .run { send in
              while !Task.isCancelled {
                try? await ContinuousClock().sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await send(.repositories(.refreshWorktrees))
              }
            }
            .cancellable(id: CancelID.periodicRefresh, cancelInFlight: true)
          )
        case .inactive, .background:
          var effects: [Effect<Action>] = [.cancel(id: CancelID.periodicRefresh)]
          if state.settings.restoreTerminalLayoutOnLaunch, !state.suppressLayoutSaveUntilRelaunch {
            appLogger.info("[LayoutRestore] scenePhase=\(String(describing: phase)), saving layout snapshot")
            effects.append(.run { _ in await terminalClient.send(.saveLayoutSnapshot) })
          }
          return .merge(effects)
        @unknown default:
          return .cancel(id: CancelID.periodicRefresh)
        }

      case .repositories(.delegate(.selectedWorktreeChanged(let worktree))):
        let lastFocusedWorktreeID = state.repositories.selectedWorktreeID
        let repositoryPersistence = repositoryPersistence
        let isPlainFolderSelection =
          state.repositories.selectedRepository?.capabilities.supportsRunnableFolderActions == true
          && state.repositories.selectedRepository?.capabilities.supportsWorktrees == false
        guard let worktree else {
          state.openActionSelection = .finder
          state.selectedRunScript = ""
          state.selectedCustomCommands = []
          state.resolvedKeybindings = resolvedKeybindings(
            settings: state.settings,
            customCommands: state.selectedCustomCommands
          )
          state.runScriptDraft = ""
          state.isRunScriptPromptPresented = false
          var effects: [Effect<Action>] = [
            .run { _ in
              await terminalClient.send(.setSelectedWorktreeID(nil))
            },
            .run { _ in
              await worktreeInfoWatcher.send(.setSelectedWorktreeID(nil))
            },
          ]
          if !state.repositories.isShowingArchivedWorktrees, !state.repositories.isShowingCanvas {
            effects.insert(
              .run { _ in
                await repositoryPersistence.saveLastFocusedWorktreeID(lastFocusedWorktreeID)
              },
              at: 0
            )
          }
          return .merge(
            .merge(effects),
            .run { _ in
              await customShortcutRegistryClient.setShortcuts([])
            }
          )
        }
        let rootURL = worktree.repositoryRootURL
        let worktreeID = worktree.id
        state.selectedCustomCommands = []
        state.resolvedKeybindings = resolvedKeybindings(
          settings: state.settings,
          customCommands: state.selectedCustomCommands
        )
        state.runScriptDraft = ""
        state.isRunScriptPromptPresented = false
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        @Shared(.userRepositorySettings(rootURL)) var userRepositorySettings
        let settings = repositorySettings
        let userSettings = userRepositorySettings
        var effects: [Effect<Action>] = []
        if !isPlainFolderSelection {
          effects.append(
            .run { _ in
              await repositoryPersistence.saveLastFocusedWorktreeID(lastFocusedWorktreeID)
            }
          )
        }
        effects.append(
          .run { _ in
            await terminalClient.send(.setSelectedWorktreeID(worktree.id))
          }
        )
        effects.append(
          .run { _ in
            await worktreeInfoWatcher.send(.setSelectedWorktreeID(isPlainFolderSelection ? nil : worktree.id))
          }
        )
        effects.append(
          .run { _ in
            await customShortcutRegistryClient.setShortcuts([])
          }
        )
        effects.append(
          .concatenate(
            .send(.worktreeSettingsLoaded(settings, worktreeID: worktreeID)),
            .send(.worktreeUserSettingsLoaded(userSettings, worktreeID: worktreeID))
          )
        )
        return .merge(effects)

      case .repositories(.delegate(.worktreeCreated(let worktree))):
        let shouldRunSetupScript =
          state.repositories.pendingSetupScriptWorktreeIDs.contains(worktree.id)
        return .run { _ in
          await terminalClient.send(
            .ensureInitialTab(
              worktree,
              runSetupScriptIfNew: shouldRunSetupScript,
              focusing: false
            )
          )
        }

      case .repositories(.delegate(.repositoriesChanged(let repositories))):
        let archivedIDs = state.repositories.archivedWorktreeIDSet
        let ids = state.repositories.terminalStateIDs.subtracting(archivedIDs)
        let recencyIDs = CommandPaletteFeature.recencyRetentionIDs(from: repositories)
        let worktrees = state.repositories.worktreesForInfoWatcher()
        let shouldRestoreLayout =
          state.launchRestoreMode == .restoreLayout
          && state.repositories.snapshotPersistencePhase == .active
        appLogger.info(
          "[LayoutRestore] repositoriesChanged: mode=\(String(describing: state.launchRestoreMode))"
            + " phase=\(String(describing: state.repositories.snapshotPersistencePhase))"
            + " → shouldRestore=\(shouldRestoreLayout)"
        )
        if shouldRestoreLayout {
          state.launchRestoreMode = .lastFocusedWorktree
          state.repositories.selection = nil
        }
        state.runScriptStatusByWorktreeID = state.runScriptStatusByWorktreeID.filter { ids.contains($0.key) }
        let restorableWorktrees = makeTerminalRestorableWorktrees(from: Array(repositories))
        appLogger.info("[LayoutRestore] restorableWorktrees count=\(restorableWorktrees.count)")
        if case .repository(let repositoryID)? = state.settings.selection,
          !repositories.contains(where: { $0.id == repositoryID })
        {
          var effects: [Effect<Action>] = [
            .send(.settings(.setSelection(.general))),
            .send(.commandPalette(.pruneRecency(recencyIDs))),
            .run { _ in
              await terminalClient.send(.prune(ids))
            },
            .run { _ in
              await worktreeInfoWatcher.send(.setWorktrees(worktrees))
            },
          ]
          if shouldRestoreLayout {
            effects.append(
              .run { _ in
                await terminalClient.send(.restoreLayoutSnapshot(worktrees: restorableWorktrees))
              }
            )
          }
          return .merge(effects)
        }
        var effects: [Effect<Action>] = [
          .send(.commandPalette(.pruneRecency(recencyIDs))),
          .run { _ in
            await terminalClient.send(.prune(ids))
          },
          .run { _ in
            await worktreeInfoWatcher.send(.setWorktrees(worktrees))
          },
        ]
        if shouldRestoreLayout {
          effects.append(
            .run { _ in
              await terminalClient.send(.restoreLayoutSnapshot(worktrees: restorableWorktrees))
            }
          )
        }
        return .merge(effects)

      case .repositories(.delegate(.openRepositorySettings(let repositoryID))):
        guard state.repositories.repositories.contains(where: { $0.id == repositoryID }) else {
          return .none
        }
        let selection = SettingsSection.repository(repositoryID)
        return .merge(
          .send(.settings(.setSelection(selection))),
          .run { _ in
            await settingsWindowClient.show()
          }
        )

      case .settings(.setSelection(let selection)):
        let resolvedSelection = selection ?? .general
        switch resolvedSelection {
        case .repository(let repositoryID):
          guard let repository = state.repositories.repositories[id: repositoryID] else {
            state.settings.repositorySettings = nil
            return .none
          }
          @Shared(.repositorySettings(repository.rootURL)) var repositorySettings
          @Shared(.userRepositorySettings(repository.rootURL)) var userRepositorySettings
          state.settings.repositorySettings = RepositorySettingsFeature.State(
            rootURL: repository.rootURL,
            repositoryKind: repository.kind,
            settings: repositorySettings,
            userSettings: userRepositorySettings
          )
        case .general, .notifications, .shortcuts, .worktree, .updates, .advanced, .github:
          state.settings.repositorySettings = nil
        }
        return .none

      case .settings(.delegate(.settingsChanged(let settings))):
        let shouldCheckSystemNotificationPermission =
          settings.systemNotificationsEnabled && !state.lastKnownSystemNotificationsEnabled
        state.lastKnownSystemNotificationsEnabled = settings.systemNotificationsEnabled
        state.settings.keybindingUserOverrides = settings.keybindingUserOverrides
        if let selectedWorktree = state.repositories.selectedTerminalWorktree {
          let rootURL = selectedWorktree.repositoryRootURL
          @Shared(.repositorySettings(rootURL)) var repositorySettings
          state.openActionSelection = OpenWorktreeAction.fromSettingsID(
            repositorySettings.openActionID,
            defaultEditorID: settings.defaultEditorID
          )
        }
        state.resolvedKeybindings = resolvedKeybindings(
          settings: state.settings,
          customCommands: state.selectedCustomCommands
        )
        return .merge(
          .send(.repositories(.setGithubIntegrationEnabled(settings.githubIntegrationEnabled))),
          .send(
            .repositories(
              .setAutomaticallyArchiveMergedWorktrees(
                settings.automaticallyArchiveMergedWorktrees
              )
            )
          ),
          .send(
            .repositories(
              .setMoveNotifiedWorktreeToTop(
                settings.moveNotifiedWorktreeToTop
              )
            )
          ),
          .send(
            .updates(
              .applySettings(
                updateChannel: settings.updateChannel,
                automaticallyChecks: settings.updatesAutomaticallyCheckForUpdates,
                automaticallyDownloads: settings.updatesAutomaticallyDownloadUpdates
              )
            )
          ),
          .run { _ in
            await terminalClient.send(.setNotificationsEnabled(settings.inAppNotificationsEnabled))
          },
          .run { _ in
            await terminalClient.send(
              .setCommandFinishedNotification(
                enabled: settings.commandFinishedNotificationEnabled,
                threshold: settings.commandFinishedNotificationThreshold
              )
            )
          },
          .run { _ in
            await worktreeInfoWatcher.send(
              .setPullRequestTrackingEnabled(settings.githubIntegrationEnabled)
            )
          },
          .run { send in
            guard shouldCheckSystemNotificationPermission else { return }
            let status = await systemNotificationClient.authorizationStatus()
            switch status {
            case .authorized:
              return
            case .notDetermined:
              let result = await systemNotificationClient.requestAuthorization()
              if !result.granted {
                await send(
                  .systemNotificationsPermissionFailed(errorMessage: result.errorMessage)
                )
              }
            case .denied:
              await send(.systemNotificationsPermissionFailed(errorMessage: "Authorization status is denied."))
            }
          }
        )

      case .settings(.delegate(.terminalFontSizeChanged)):
        return .none

      case .settings(.delegate(.terminalLayoutSnapshotCleared(let success))):
        if success {
          state.suppressLayoutSaveUntilRelaunch = true
          return .send(.repositories(.showToast(.success("Saved terminal layout cleared"))))
        }
        return .send(
          .repositories(
            .presentAlert(
              title: "Unable to clear saved terminal layout",
              message: "Please check file permissions and try again."
            )
          )
        )

      case .openActionSelectionChanged(let action):
        state.openActionSelection = action
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        let rootURL = worktree.repositoryRootURL
        let actionID = action.settingsID
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        $repositorySettings.withLock { $0.openActionID = actionID }
        return .none

      case .openSelectedWorktree:
        return .send(.openWorktree(OpenWorktreeAction.availableSelection(state.openActionSelection)))

      case .openWorktree(let action):
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        analyticsClient.capture("worktree_opened", ["action": action.settingsID])
        if action == .editor {
          let shouldRunSetupScript =
            state.repositories.pendingSetupScriptWorktreeIDs.contains(worktree.id)
          return .run { _ in
            await terminalClient.send(
              .createTabWithInput(
                worktree,
                input: "$EDITOR",
                runSetupScriptIfNew: shouldRunSetupScript
              )
            )
          }
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

      case .requestQuit:
        #if !DEBUG
          guard state.settings.confirmBeforeQuit else {
            analyticsClient.capture("app_quit", nil)
            return .run { @MainActor _ in
              NSApplication.shared.terminate(nil)
            }
          }
          state.alert = AlertState {
            TextState("Quit Prowl?")
          } actions: {
            ButtonState(action: .confirmQuit) {
              TextState("Quit")
            }
            ButtonState(role: .cancel, action: .dismiss) {
              TextState("Cancel")
            }
          } message: {
            TextState("This will close all terminal sessions.")
          }
          return .none
        #else
          return .run { @MainActor _ in
            NSApplication.shared.terminate(nil)
          }
        #endif

      case .newTerminal:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        analyticsClient.capture("terminal_tab_created", nil)
        let shouldRunSetupScript = state.repositories.pendingSetupScriptWorktreeIDs.contains(worktree.id)
        return .run { _ in
          await terminalClient.send(.createTab(worktree, runSetupScriptIfNew: shouldRunSetupScript))
        }

      case .runScript:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        let trimmed = state.selectedRunScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          if state.isRunScriptPromptPresented {
            return .none
          }
          state.runScriptDraft = state.selectedRunScript
          state.isRunScriptPromptPresented = true
          return .none
        }
        analyticsClient.capture("script_run", nil)
        let script = state.selectedRunScript
        return .run { _ in
          await terminalClient.send(.runScript(worktree, script: script))
        }

      case .runCustomCommand(let index):
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        guard state.selectedCustomCommands.indices.contains(index) else {
          return .none
        }
        let customCommand = state.selectedCustomCommands[index]
        guard customCommand.hasRunnableCommand else {
          return .none
        }
        let command = customCommand.command
        switch customCommand.execution {
        case .shellScript:
          return .run { _ in
            await terminalClient.send(
              .createTabWithInput(
                worktree,
                input: command,
                runSetupScriptIfNew: false
              )
            )
          }
        case .terminalInput:
          return .run { _ in
            await terminalClient.send(.insertText(worktree, text: command))
          }
        }

      case .runScriptDraftChanged(let script):
        state.runScriptDraft = script
        return .none

      case .runScriptPromptPresented(let isPresented):
        state.isRunScriptPromptPresented = isPresented
        if !isPresented {
          state.runScriptDraft = ""
        }
        return .none

      case .saveRunScriptAndRun:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          state.isRunScriptPromptPresented = false
          state.runScriptDraft = ""
          return .none
        }
        let script = state.runScriptDraft
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          return .none
        }
        let rootURL = worktree.repositoryRootURL
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        $repositorySettings.withLock { $0.runScript = script }
        if state.settings.repositorySettings?.rootURL == rootURL {
          state.settings.repositorySettings?.settings.runScript = script
        }
        state.selectedRunScript = script
        state.isRunScriptPromptPresented = false
        state.runScriptDraft = ""
        return .send(.runScript)

      case .stopRunScript:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.stopRunScript(worktree))
        }

      case .closeTab:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        analyticsClient.capture("terminal_tab_closed", nil)
        return .run { _ in
          await terminalClient.send(.closeFocusedTab(worktree))
        }

      case .closeSurface:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.closeFocusedSurface(worktree))
        }

      case .startSearch:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.startSearch(worktree))
        }

      case .searchSelection:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.searchSelection(worktree))
        }

      case .navigateSearchNext:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.navigateSearchNext(worktree))
        }

      case .navigateSearchPrevious:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.navigateSearchPrevious(worktree))
        }

      case .endSearch:
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.endSearch(worktree))
        }

      case .settings(.repositorySettings(.delegate(.settingsChanged(let rootURL)))):
        guard let selectedWorktree = state.repositories.selectedTerminalWorktree,
          selectedWorktree.repositoryRootURL == rootURL
        else {
          return .none
        }
        let worktreeID = selectedWorktree.id
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        @Shared(.userRepositorySettings(rootURL)) var userRepositorySettings
        return .concatenate(
          .send(.worktreeSettingsLoaded(repositorySettings, worktreeID: worktreeID)),
          .send(.worktreeUserSettingsLoaded(userRepositorySettings, worktreeID: worktreeID))
        )

      case .worktreeSettingsLoaded(let settings, let worktreeID):
        guard state.repositories.selectedTerminalWorktree?.id == worktreeID else {
          return .none
        }
        @Shared(.settingsFile) var settingsFile
        let normalizedDefaultEditorID = OpenWorktreeAction.normalizedDefaultEditorID(
          settingsFile.global.defaultEditorID
        )
        state.openActionSelection = OpenWorktreeAction.fromSettingsID(
          settings.openActionID,
          defaultEditorID: normalizedDefaultEditorID
        )
        state.selectedRunScript = settings.runScript
        return .none

      case .worktreeUserSettingsLoaded(let settings, let worktreeID):
        guard state.repositories.selectedTerminalWorktree?.id == worktreeID else {
          return .none
        }
        state.selectedCustomCommands = UserRepositorySettings.normalizedCommands(settings.customCommands)
        state.resolvedKeybindings = resolvedKeybindings(
          settings: state.settings,
          customCommands: state.selectedCustomCommands
        )
        let userOverrideConflicts = AppShortcuts.userOverrideConflicts(in: state.selectedCustomCommands)
        let shortcuts: [UserCustomShortcut] = state.selectedCustomCommands.compactMap { command in
          let commandID = LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id)
          return state.resolvedKeybindings.keybinding(for: commandID)?.userCustomShortcut
        }
        return .run { _ in
          let logger = SupaLogger("Shortcuts")
          for conflict in userOverrideConflicts {
            logger.warning(
              "shortcut_conflict reason=userOverride app_action=\"\(conflict.appActionTitle)\" "
                + "app_shortcut=\(conflict.appShortcutDisplay) custom_command=\"\(conflict.commandTitle)\" "
                + "custom_shortcut=\(conflict.commandShortcutDisplay) result=customOverride"
            )
          }
          await customShortcutRegistryClient.setShortcuts(shortcuts)
        }

      case .systemNotificationsPermissionFailed(let errorMessage):
        return .concatenate(
          .send(.settings(.setSystemNotificationsEnabled(false))),
          .send(.settings(.showNotificationPermissionAlert(errorMessage: errorMessage)))
        )

      case .alert(.dismiss):
        state.alert = nil
        return .none

      case .alert(.presented(.confirmQuit)):
        analyticsClient.capture("app_quit", nil)
        state.alert = nil
        return .run { @MainActor _ in
          NSApplication.shared.terminate(nil)
        }

      case .alert:
        return .none

      case .repositories:
        return .none

      case .settings:
        return .none

      case .updates:
        return .none

      case .commandPalette(.delegate(.selectWorktree(let worktreeID))):
        return .send(.repositories(.selectWorktree(worktreeID)))

      case .commandPalette(.delegate(.checkForUpdates)):
        return .send(.updates(.checkForUpdates))

      case .commandPalette(.delegate(.openSettings)):
        return .merge(
          .send(.settings(.setSelection(.general))),
          .run { _ in
            await settingsWindowClient.show()
          }
        )

      case .commandPalette(.delegate(.newWorktree)):
        return .send(.repositories(.createRandomWorktree))

      case .commandPalette(.delegate(.openRepository)):
        return .send(.repositories(.setOpenPanelPresented(true)))

      case .commandPalette(.delegate(.removeWorktree(let worktreeID, let repositoryID))):
        return .send(.repositories(.requestDeleteWorktree(worktreeID, repositoryID)))

      case .commandPalette(.delegate(.archiveWorktree(let worktreeID, let repositoryID))):
        return .send(.repositories(.requestArchiveWorktree(worktreeID, repositoryID)))

      case .commandPalette(.delegate(.refreshWorktrees)):
        return .send(.repositories(.refreshWorktrees))

      case .commandPalette(.delegate(.ghosttyCommand(let action))):
        guard let worktree = state.repositories.selectedTerminalWorktree else {
          return .none
        }
        return .run { _ in
          await terminalClient.send(.performBindingAction(worktree, action: action))
        }

      case .commandPalette(.delegate(.openPullRequest(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .openOnGithub)))

      case .commandPalette(.delegate(.markPullRequestReady(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .markReadyForReview)))

      case .commandPalette(.delegate(.mergePullRequest(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .merge)))

      case .commandPalette(.delegate(.closePullRequest(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .close)))

      case .commandPalette(.delegate(.copyFailingJobURL(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .copyFailingJobURL)))

      case .commandPalette(.delegate(.copyCiFailureLogs(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .copyCiFailureLogs)))

      case .commandPalette(.delegate(.rerunFailedJobs(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .rerunFailedJobs)))

      case .commandPalette(.delegate(.openFailingCheckDetails(let worktreeID))):
        return .send(.repositories(.pullRequestAction(worktreeID, .openFailingCheckDetails)))

      #if DEBUG
        case .commandPalette(.delegate(.debugTestToast(let toast))):
          return .send(.repositories(.showToast(toast)))
      #endif

      case .commandPalette:
        return .none

      case .terminalEvent(.notificationReceived(let worktreeID, let title, let body)):
        var effects: [Effect<Action>] = [
          .send(.repositories(.worktreeNotificationReceived(worktreeID)))
        ]
        if state.settings.systemNotificationsEnabled {
          effects.append(
            .run { _ in
              await systemNotificationClient.send(title, body)
            }
          )
        }
        if state.settings.notificationSoundEnabled && !state.settings.systemNotificationsEnabled {
          effects.append(
            .run { _ in
              await notificationSoundClient.play()
            }
          )
        }
        return .merge(effects)

      case .terminalEvent(.notificationIndicatorChanged(let count)):
        state.notificationIndicatorCount = count
        return .run { _ in
          await MainActor.run {
            NSApplication.shared.dockTile.badgeLabel = nil
          }
        }

      case .terminalEvent(.runScriptStatusChanged(let worktreeID, let isRunning)):
        if isRunning {
          state.runScriptStatusByWorktreeID[worktreeID] = true
        } else {
          state.runScriptStatusByWorktreeID.removeValue(forKey: worktreeID)
        }
        return .none

      case .terminalEvent(.commandPaletteToggleRequested(let worktreeID)):
        if state.commandPalette.isPresented {
          return .send(.commandPalette(.setPresented(false)))
        }
        if state.repositories.worktree(for: worktreeID) != nil {
          return .merge(
            .send(.repositories(.selectWorktree(worktreeID))),
            .send(.commandPalette(.setPresented(true)))
          )
        }
        if state.repositories.repositories[id: worktreeID]?.kind == .plain {
          return .merge(
            .send(.repositories(.selectRepository(worktreeID))),
            .send(.commandPalette(.setPresented(true)))
          )
        }
        return .send(.commandPalette(.setPresented(true)))
      case .terminalEvent(.setupScriptConsumed(let worktreeID)):
        return .send(.repositories(.consumeSetupScript(worktreeID)))

      case .terminalEvent(.fontSizeChanged(let fontSize)):
        return .send(.settings(.setTerminalFontSize(fontSize)))

      case .terminalEvent(.layoutRestored(let selectedWorktreeID)):
        appLogger.info("[LayoutRestore] layoutRestored: selectedWorktreeID=\(selectedWorktreeID ?? "nil")")
        if let selectedWorktreeID {
          // Plain folders use .repository selection, not .worktree
          if let repo = state.repositories.repositories[id: selectedWorktreeID],
            repo.kind == .plain
          {
            return .send(.repositories(.selectRepository(selectedWorktreeID)))
          }
          return .send(.repositories(.selectWorktree(selectedWorktreeID)))
        }
        return .none

      case .terminalEvent(.layoutRestoreFailed(let message)):
        appLogger.warning("[LayoutRestore] layoutRestoreFailed: \(message)")
        return .send(.repositories(.showToast(.warning(message))))

      case .terminalEvent:
        return .none
      }
    }
    core
    Scope(state: \.repositories, action: \.repositories) {
      RepositoriesFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Scope(state: \.updates, action: \.updates) {
      UpdatesFeature()
    }
    Scope(state: \.commandPalette, action: \.commandPalette) {
      CommandPaletteFeature()
    }
  }
}
