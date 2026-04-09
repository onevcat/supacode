import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var appearanceMode: AppearanceMode
    var defaultEditorID: String
    var confirmBeforeQuit: Bool
    var updateChannel: UpdateChannel
    var updatesAutomaticallyCheckForUpdates: Bool
    var updatesAutomaticallyDownloadUpdates: Bool
    var inAppNotificationsEnabled: Bool
    var notificationSoundEnabled: Bool
    var systemNotificationsEnabled: Bool
    var moveNotifiedWorktreeToTop: Bool
    var commandFinishedNotificationEnabled: Bool
    var commandFinishedNotificationThreshold: Int
    var analyticsEnabled: Bool
    var crashReportsEnabled: Bool
    var githubIntegrationEnabled: Bool
    var deleteBranchOnDeleteWorktree: Bool
    var automaticallyArchiveMergedWorktrees: Bool
    var archivedAutoDeletePeriod: AutoDeletePeriod?
    var promptForWorktreeCreation: Bool
    var defaultWorktreeBaseDirectoryPath: String
    var restoreTerminalLayoutOnLaunch: Bool
    var terminalFontSize: Float32?
    var keybindingUserOverrides: KeybindingUserOverrideStore
    var cliInstallStatus: CLIInstallStatus = .notInstalled
    var cliInstallShowAlert: Bool = true
    var selection: SettingsSection? = .general
    var repositorySettings: RepositorySettingsFeature.State?
    @Presents var alert: AlertState<Alert>?

    init(settings: GlobalSettings = .default) {
      let normalizedDefaultEditorID = OpenWorktreeAction.normalizedDefaultEditorID(settings.defaultEditorID)
      appearanceMode = settings.appearanceMode
      defaultEditorID = normalizedDefaultEditorID
      confirmBeforeQuit = settings.confirmBeforeQuit
      updateChannel = settings.updateChannel
      updatesAutomaticallyCheckForUpdates = settings.updatesAutomaticallyCheckForUpdates
      updatesAutomaticallyDownloadUpdates = settings.updatesAutomaticallyDownloadUpdates
      inAppNotificationsEnabled = settings.inAppNotificationsEnabled
      notificationSoundEnabled = settings.notificationSoundEnabled
      systemNotificationsEnabled = settings.systemNotificationsEnabled
      moveNotifiedWorktreeToTop = settings.moveNotifiedWorktreeToTop
      commandFinishedNotificationEnabled = settings.commandFinishedNotificationEnabled
      commandFinishedNotificationThreshold = settings.commandFinishedNotificationThreshold
      analyticsEnabled = settings.analyticsEnabled
      crashReportsEnabled = settings.crashReportsEnabled
      githubIntegrationEnabled = settings.githubIntegrationEnabled
      deleteBranchOnDeleteWorktree = settings.deleteBranchOnDeleteWorktree
      automaticallyArchiveMergedWorktrees = settings.automaticallyArchiveMergedWorktrees
      archivedAutoDeletePeriod = settings.archivedAutoDeletePeriod
      promptForWorktreeCreation = settings.promptForWorktreeCreation
      defaultWorktreeBaseDirectoryPath =
        SupacodePaths.normalizedWorktreeBaseDirectoryPath(settings.defaultWorktreeBaseDirectoryPath) ?? ""
      restoreTerminalLayoutOnLaunch = settings.restoreTerminalLayoutOnLaunch
      terminalFontSize = settings.terminalFontSize
      keybindingUserOverrides = settings.keybindingUserOverrides
    }

    var globalSettings: GlobalSettings {
      GlobalSettings(
        appearanceMode: appearanceMode,
        defaultEditorID: defaultEditorID,
        confirmBeforeQuit: confirmBeforeQuit,
        updateChannel: updateChannel,
        updatesAutomaticallyCheckForUpdates: updatesAutomaticallyCheckForUpdates,
        updatesAutomaticallyDownloadUpdates: updatesAutomaticallyDownloadUpdates,
        inAppNotificationsEnabled: inAppNotificationsEnabled,
        notificationSoundEnabled: notificationSoundEnabled,
        systemNotificationsEnabled: systemNotificationsEnabled,
        moveNotifiedWorktreeToTop: moveNotifiedWorktreeToTop,
        commandFinishedNotificationEnabled: commandFinishedNotificationEnabled,
        commandFinishedNotificationThreshold: commandFinishedNotificationThreshold,
        analyticsEnabled: analyticsEnabled,
        crashReportsEnabled: crashReportsEnabled,
        githubIntegrationEnabled: githubIntegrationEnabled,
        deleteBranchOnDeleteWorktree: deleteBranchOnDeleteWorktree,
        automaticallyArchiveMergedWorktrees: automaticallyArchiveMergedWorktrees,
        promptForWorktreeCreation: promptForWorktreeCreation,
        defaultWorktreeBaseDirectoryPath: SupacodePaths.normalizedWorktreeBaseDirectoryPath(
          defaultWorktreeBaseDirectoryPath
        ),
        restoreTerminalLayoutOnLaunch: restoreTerminalLayoutOnLaunch,
        archivedAutoDeletePeriod: archivedAutoDeletePeriod,
        terminalFontSize: terminalFontSize,
        keybindingUserOverrides: keybindingUserOverrides
      )
    }
  }

  enum Action: BindableAction {
    case task
    case settingsLoaded(GlobalSettings)
    case setSelection(SettingsSection?)
    case setSystemNotificationsEnabled(Bool)
    case setCommandFinishedNotificationThreshold(String)
    case setTerminalFontSize(Float32?)
    case clearTerminalLayoutSnapshotButtonTapped
    case installCLIButtonTapped(showAlert: Bool = true)
    case uninstallCLIButtonTapped
    case cliInstallCompleted(Result<String, CLIInstallError>)
    case refreshCLIInstallStatus
    case showNotificationPermissionAlert(errorMessage: String?)
    case repositorySettings(RepositorySettingsFeature.Action)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
    case binding(BindingAction<State>)
  }

  enum Alert: Equatable {
    case dismiss
    case openSystemNotificationSettings
  }

  enum CLIInstallResultMessage: Equatable {
    case installed(path: String)
    case uninstalled
    case failed(message: String)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(GlobalSettings)
    case terminalFontSizeChanged(Float32?)
    case terminalLayoutSnapshotCleared(success: Bool)
    case cliInstallCompleted(CLIInstallResultMessage)
  }

  @Dependency(AnalyticsClient.self) private var analyticsClient
  @Dependency(SystemNotificationClient.self) private var systemNotificationClient
  @Dependency(TerminalLayoutPersistenceClient.self) private var terminalLayoutPersistence
  @Dependency(CLIInstallClient.self) private var cliInstallClient

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        @Shared(.settingsFile) var settingsFile
        return .send(.settingsLoaded(settingsFile.global))

      case .settingsLoaded(let settings):
        let normalizedDefaultEditorID = OpenWorktreeAction.normalizedDefaultEditorID(settings.defaultEditorID)
        let normalizedWorktreeBaseDirPath =
          SupacodePaths.normalizedWorktreeBaseDirectoryPath(settings.defaultWorktreeBaseDirectoryPath)
        let normalizedSettings: GlobalSettings
        if normalizedDefaultEditorID == settings.defaultEditorID,
          normalizedWorktreeBaseDirPath == settings.defaultWorktreeBaseDirectoryPath
        {
          normalizedSettings = settings
        } else {
          var updatedSettings = settings
          updatedSettings.defaultEditorID = normalizedDefaultEditorID
          updatedSettings.defaultWorktreeBaseDirectoryPath = normalizedWorktreeBaseDirPath
          normalizedSettings = updatedSettings
          @Shared(.settingsFile) var settingsFile
          $settingsFile.withLock { $0.global = normalizedSettings }
        }
        state.appearanceMode = normalizedSettings.appearanceMode
        state.defaultEditorID = normalizedSettings.defaultEditorID
        state.confirmBeforeQuit = normalizedSettings.confirmBeforeQuit
        state.updateChannel = normalizedSettings.updateChannel
        state.updatesAutomaticallyCheckForUpdates = normalizedSettings.updatesAutomaticallyCheckForUpdates
        state.updatesAutomaticallyDownloadUpdates = normalizedSettings.updatesAutomaticallyDownloadUpdates
        state.inAppNotificationsEnabled = normalizedSettings.inAppNotificationsEnabled
        state.notificationSoundEnabled = normalizedSettings.notificationSoundEnabled
        state.systemNotificationsEnabled = normalizedSettings.systemNotificationsEnabled
        state.moveNotifiedWorktreeToTop = normalizedSettings.moveNotifiedWorktreeToTop
        state.commandFinishedNotificationEnabled = normalizedSettings.commandFinishedNotificationEnabled
        state.commandFinishedNotificationThreshold = normalizedSettings.commandFinishedNotificationThreshold
        state.analyticsEnabled = normalizedSettings.analyticsEnabled
        state.crashReportsEnabled = normalizedSettings.crashReportsEnabled
        state.githubIntegrationEnabled = normalizedSettings.githubIntegrationEnabled
        state.deleteBranchOnDeleteWorktree = normalizedSettings.deleteBranchOnDeleteWorktree
        state.automaticallyArchiveMergedWorktrees = normalizedSettings.automaticallyArchiveMergedWorktrees
        state.archivedAutoDeletePeriod = normalizedSettings.archivedAutoDeletePeriod
        state.promptForWorktreeCreation = normalizedSettings.promptForWorktreeCreation
        state.defaultWorktreeBaseDirectoryPath = normalizedSettings.defaultWorktreeBaseDirectoryPath ?? ""
        state.restoreTerminalLayoutOnLaunch = normalizedSettings.restoreTerminalLayoutOnLaunch
        state.terminalFontSize = normalizedSettings.terminalFontSize
        state.keybindingUserOverrides = normalizedSettings.keybindingUserOverrides
        state.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath =
          normalizedSettings.defaultWorktreeBaseDirectoryPath
        return .send(.delegate(.settingsChanged(normalizedSettings)))

      case .binding:
        state.commandFinishedNotificationThreshold = min(max(state.commandFinishedNotificationThreshold, 0), 600)
        let defaultWorktreeBaseDirectoryPath = state.globalSettings.defaultWorktreeBaseDirectoryPath
        state.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath =
          defaultWorktreeBaseDirectoryPath
        return persist(state)

      case .setCommandFinishedNotificationThreshold(let text):
        if let parsed = Int(text) {
          state.commandFinishedNotificationThreshold = min(max(parsed, 0), 600)
        } else {
          state.commandFinishedNotificationThreshold = 10
        }
        return persist(state)

      case .setSystemNotificationsEnabled(let isEnabled):
        state.systemNotificationsEnabled = isEnabled
        let defaultWorktreeBaseDirectoryPath = state.globalSettings.defaultWorktreeBaseDirectoryPath
        state.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath =
          defaultWorktreeBaseDirectoryPath
        return persist(state)

      case .setTerminalFontSize(let fontSize):
        guard state.terminalFontSize != fontSize else { return .none }
        state.terminalFontSize = fontSize
        return .merge(
          persist(state, captureAnalytics: false, emitSettingsChanged: false),
          .send(.delegate(.terminalFontSizeChanged(fontSize)))
        )

      case .clearTerminalLayoutSnapshotButtonTapped:
        return .run { send in
          let success = await terminalLayoutPersistence.clearSnapshot()
          await send(.delegate(.terminalLayoutSnapshotCleared(success: success)))
        }

      case .installCLIButtonTapped(let showAlert):
        state.cliInstallShowAlert = showAlert
        let installPath = cliDefaultInstallPath
        return .run { [cliInstallClient] send in
          do {
            try await cliInstallClient.install(installPath)
            let path = installPath.path(percentEncoded: false)
            await send(.cliInstallCompleted(.success(path)))
          } catch let error as CLIInstallError {
            await send(.cliInstallCompleted(.failure(error)))
          } catch {
            await send(.cliInstallCompleted(.failure(CLIInstallError(message: error.localizedDescription))))
          }
        }

      case .uninstallCLIButtonTapped:
        let installPath = cliDefaultInstallPath
        return .run { [cliInstallClient] send in
          do {
            try await cliInstallClient.uninstall(installPath)
            await send(.cliInstallCompleted(.success("")))
          } catch let error as CLIInstallError {
            await send(.cliInstallCompleted(.failure(error)))
          } catch {
            await send(.cliInstallCompleted(.failure(CLIInstallError(message: error.localizedDescription))))
          }
        }

      case .cliInstallCompleted(.success(let path)):
        if state.cliInstallShowAlert {
          if path.isEmpty {
            state.alert = AlertState {
              TextState("Command Line Tool Uninstalled")
            } actions: {
              ButtonState(action: .dismiss) { TextState("OK") }
            } message: {
              TextState("The prowl command line tool has been removed.")
            }
          } else {
            state.alert = AlertState {
              TextState("Command Line Tool Installed")
            } actions: {
              ButtonState(action: .dismiss) { TextState("OK") }
            } message: {
              TextState("The prowl command is now available at \(path).")
            }
          }
        }
        state.cliInstallStatus = cliInstallClient.installationStatus(cliDefaultInstallPath)
        let result: CLIInstallResultMessage = path.isEmpty ? .uninstalled : .installed(path: path)
        return .send(.delegate(.cliInstallCompleted(result)))

      case .cliInstallCompleted(.failure(let error)):
        if state.cliInstallShowAlert {
          state.alert = AlertState {
            TextState("Command Line Tool Error")
          } actions: {
            ButtonState(action: .dismiss) { TextState("OK") }
          } message: {
            TextState(error.message)
          }
        }
        state.cliInstallStatus = cliInstallClient.installationStatus(cliDefaultInstallPath)
        return .send(.delegate(.cliInstallCompleted(.failed(message: error.message))))

      case .refreshCLIInstallStatus:
        state.cliInstallStatus = cliInstallClient.installationStatus(cliDefaultInstallPath)
        return .none

      case .showNotificationPermissionAlert(let errorMessage):
        let message: String
        if let errorMessage, !errorMessage.isEmpty {
          message =
            "Prowl cannot send system notifications.\n\n"
            + "Error: \(errorMessage)"
        } else {
          message = "Prowl cannot send system notifications while permission is denied."
        }
        state.alert = AlertState {
          TextState("Enable Notifications in System Settings")
        } actions: {
          ButtonState(action: .openSystemNotificationSettings) {
            TextState("Open System Settings")
          }
          ButtonState(role: .cancel, action: .dismiss) {
            TextState("Cancel")
          }
        } message: {
          TextState(message)
        }
        return .none

      case .setSelection(let selection):
        state.selection = selection ?? .general
        return .none

      case .alert(.dismiss):
        state.alert = nil
        return .none

      case .alert(.presented(.openSystemNotificationSettings)):
        state.alert = nil
        return .run { _ in
          await systemNotificationClient.openSettings()
        }

      case .alert:
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

  private func persist(
    _ state: State,
    captureAnalytics: Bool = true,
    emitSettingsChanged: Bool = true
  ) -> Effect<Action> {
    let settings = state.globalSettings
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = settings }
    if captureAnalytics, settings.analyticsEnabled {
      analyticsClient.capture("settings_changed", nil)
    }
    if emitSettingsChanged {
      return .send(.delegate(.settingsChanged(settings)))
    }
    return .none
  }
}
