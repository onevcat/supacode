nonisolated struct GlobalSettings: Codable, Equatable, Sendable {
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
  var mergedWorktreeAction: MergedWorktreeAction?
  var promptForWorktreeCreation: Bool
  var fetchOriginBeforeWorktreeCreation: Bool
  var defaultWorktreeBaseDirectoryPath: String?
  var copyIgnoredOnWorktreeCreate: Bool
  var copyUntrackedOnWorktreeCreate: Bool
  var pullRequestMergeStrategy: PullRequestMergeStrategy
  var restoreTerminalLayoutOnLaunch: Bool
  var terminalFontSize: Float32?
  var archivedAutoDeletePeriod: AutoDeletePeriod?
  var keybindingUserOverrides: KeybindingUserOverrideStore
  var defaultViewMode: DefaultViewMode

  static let `default` = GlobalSettings(
    appearanceMode: .dark,
    defaultEditorID: OpenWorktreeAction.automaticSettingsID,
    confirmBeforeQuit: true,
    updateChannel: .stable,
    updatesAutomaticallyCheckForUpdates: true,
    updatesAutomaticallyDownloadUpdates: false,
    inAppNotificationsEnabled: true,
    notificationSoundEnabled: true,
    systemNotificationsEnabled: false,
    moveNotifiedWorktreeToTop: true,
    commandFinishedNotificationEnabled: true,
    commandFinishedNotificationThreshold: 10,
    analyticsEnabled: true,
    crashReportsEnabled: true,
    githubIntegrationEnabled: true,
    deleteBranchOnDeleteWorktree: true,
    mergedWorktreeAction: nil,
    promptForWorktreeCreation: true,
    fetchOriginBeforeWorktreeCreation: true,
    defaultWorktreeBaseDirectoryPath: nil,
    copyIgnoredOnWorktreeCreate: false,
    copyUntrackedOnWorktreeCreate: false,
    pullRequestMergeStrategy: .merge,
    restoreTerminalLayoutOnLaunch: false,
    archivedAutoDeletePeriod: nil,
    terminalFontSize: nil,
    keybindingUserOverrides: .empty,
    defaultViewMode: .normal
  )

  init(
    appearanceMode: AppearanceMode,
    defaultEditorID: String,
    confirmBeforeQuit: Bool,
    updateChannel: UpdateChannel,
    updatesAutomaticallyCheckForUpdates: Bool,
    updatesAutomaticallyDownloadUpdates: Bool,
    inAppNotificationsEnabled: Bool,
    notificationSoundEnabled: Bool,
    systemNotificationsEnabled: Bool = false,
    moveNotifiedWorktreeToTop: Bool,
    commandFinishedNotificationEnabled: Bool = true,
    commandFinishedNotificationThreshold: Int = 10,
    analyticsEnabled: Bool,
    crashReportsEnabled: Bool,
    githubIntegrationEnabled: Bool,
    deleteBranchOnDeleteWorktree: Bool,
    mergedWorktreeAction: MergedWorktreeAction? = nil,
    promptForWorktreeCreation: Bool,
    fetchOriginBeforeWorktreeCreation: Bool = true,
    defaultWorktreeBaseDirectoryPath: String? = nil,
    copyIgnoredOnWorktreeCreate: Bool = false,
    copyUntrackedOnWorktreeCreate: Bool = false,
    pullRequestMergeStrategy: PullRequestMergeStrategy = .merge,
    restoreTerminalLayoutOnLaunch: Bool = false,
    archivedAutoDeletePeriod: AutoDeletePeriod? = nil,
    terminalFontSize: Float32? = nil,
    keybindingUserOverrides: KeybindingUserOverrideStore = .empty,
    defaultViewMode: DefaultViewMode = .normal
  ) {
    self.appearanceMode = appearanceMode
    self.defaultEditorID = defaultEditorID
    self.confirmBeforeQuit = confirmBeforeQuit
    self.updateChannel = updateChannel
    self.updatesAutomaticallyCheckForUpdates = updatesAutomaticallyCheckForUpdates
    self.updatesAutomaticallyDownloadUpdates = updatesAutomaticallyDownloadUpdates
    self.inAppNotificationsEnabled = inAppNotificationsEnabled
    self.notificationSoundEnabled = notificationSoundEnabled
    self.systemNotificationsEnabled = systemNotificationsEnabled
    self.moveNotifiedWorktreeToTop = moveNotifiedWorktreeToTop
    self.commandFinishedNotificationEnabled = commandFinishedNotificationEnabled
    self.commandFinishedNotificationThreshold = commandFinishedNotificationThreshold
    self.analyticsEnabled = analyticsEnabled
    self.crashReportsEnabled = crashReportsEnabled
    self.githubIntegrationEnabled = githubIntegrationEnabled
    self.deleteBranchOnDeleteWorktree = deleteBranchOnDeleteWorktree
    self.mergedWorktreeAction = mergedWorktreeAction
    self.promptForWorktreeCreation = promptForWorktreeCreation
    self.fetchOriginBeforeWorktreeCreation = fetchOriginBeforeWorktreeCreation
    self.defaultWorktreeBaseDirectoryPath = defaultWorktreeBaseDirectoryPath
    self.copyIgnoredOnWorktreeCreate = copyIgnoredOnWorktreeCreate
    self.copyUntrackedOnWorktreeCreate = copyUntrackedOnWorktreeCreate
    self.pullRequestMergeStrategy = pullRequestMergeStrategy
    self.restoreTerminalLayoutOnLaunch = restoreTerminalLayoutOnLaunch
    self.archivedAutoDeletePeriod = archivedAutoDeletePeriod
    self.terminalFontSize = terminalFontSize
    self.keybindingUserOverrides = keybindingUserOverrides
    self.defaultViewMode = defaultViewMode
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(appearanceMode, forKey: .appearanceMode)
    try container.encode(defaultEditorID, forKey: .defaultEditorID)
    try container.encode(confirmBeforeQuit, forKey: .confirmBeforeQuit)
    try container.encode(updateChannel, forKey: .updateChannel)
    try container.encode(updatesAutomaticallyCheckForUpdates, forKey: .updatesAutomaticallyCheckForUpdates)
    try container.encode(updatesAutomaticallyDownloadUpdates, forKey: .updatesAutomaticallyDownloadUpdates)
    try container.encode(inAppNotificationsEnabled, forKey: .inAppNotificationsEnabled)
    try container.encode(notificationSoundEnabled, forKey: .notificationSoundEnabled)
    try container.encode(systemNotificationsEnabled, forKey: .systemNotificationsEnabled)
    try container.encode(moveNotifiedWorktreeToTop, forKey: .moveNotifiedWorktreeToTop)
    try container.encode(commandFinishedNotificationEnabled, forKey: .commandFinishedNotificationEnabled)
    try container.encode(commandFinishedNotificationThreshold, forKey: .commandFinishedNotificationThreshold)
    try container.encode(analyticsEnabled, forKey: .analyticsEnabled)
    try container.encode(crashReportsEnabled, forKey: .crashReportsEnabled)
    try container.encode(githubIntegrationEnabled, forKey: .githubIntegrationEnabled)
    try container.encode(deleteBranchOnDeleteWorktree, forKey: .deleteBranchOnDeleteWorktree)
    try container.encodeIfPresent(mergedWorktreeAction, forKey: .mergedWorktreeAction)
    try container.encode(promptForWorktreeCreation, forKey: .promptForWorktreeCreation)
    try container.encode(fetchOriginBeforeWorktreeCreation, forKey: .fetchOriginBeforeWorktreeCreation)
    try container.encodeIfPresent(defaultWorktreeBaseDirectoryPath, forKey: .defaultWorktreeBaseDirectoryPath)
    try container.encode(copyIgnoredOnWorktreeCreate, forKey: .copyIgnoredOnWorktreeCreate)
    try container.encode(copyUntrackedOnWorktreeCreate, forKey: .copyUntrackedOnWorktreeCreate)
    try container.encode(pullRequestMergeStrategy, forKey: .pullRequestMergeStrategy)
    try container.encode(restoreTerminalLayoutOnLaunch, forKey: .restoreTerminalLayoutOnLaunch)
    try container.encodeIfPresent(archivedAutoDeletePeriod?.rawValue, forKey: .archivedAutoDeletePeriod)
    try container.encodeIfPresent(terminalFontSize, forKey: .terminalFontSize)
    try container.encode(keybindingUserOverrides, forKey: .keybindingUserOverrides)
    try container.encode(defaultViewMode, forKey: .defaultViewMode)
  }

  private enum CodingKeys: String, CodingKey {
    case appearanceMode
    case defaultEditorID
    case confirmBeforeQuit
    case updateChannel
    case updatesAutomaticallyCheckForUpdates
    case updatesAutomaticallyDownloadUpdates
    case inAppNotificationsEnabled
    case notificationSoundEnabled
    case systemNotificationsEnabled
    case moveNotifiedWorktreeToTop
    case commandFinishedNotificationEnabled
    case commandFinishedNotificationThreshold
    case analyticsEnabled
    case crashReportsEnabled
    case githubIntegrationEnabled
    case deleteBranchOnDeleteWorktree
    case mergedWorktreeAction
    case promptForWorktreeCreation
    case fetchOriginBeforeWorktreeCreation
    case defaultWorktreeBaseDirectoryPath
    case copyIgnoredOnWorktreeCreate
    case copyUntrackedOnWorktreeCreate
    case pullRequestMergeStrategy
    case restoreTerminalLayoutOnLaunch
    case archivedAutoDeletePeriod
    case terminalFontSize
    case keybindingUserOverrides
    case defaultViewMode
    // Legacy key for migration
    case automaticallyArchiveMergedWorktrees
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
    defaultEditorID =
      try container.decodeIfPresent(String.self, forKey: .defaultEditorID)
      ?? Self.default.defaultEditorID
    confirmBeforeQuit =
      try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuit)
      ?? Self.default.confirmBeforeQuit
    updateChannel =
      try container.decodeIfPresent(UpdateChannel.self, forKey: .updateChannel)
      ?? Self.default.updateChannel
    updatesAutomaticallyCheckForUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyCheckForUpdates)
    updatesAutomaticallyDownloadUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyDownloadUpdates)
    inAppNotificationsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .inAppNotificationsEnabled)
      ?? Self.default.inAppNotificationsEnabled
    notificationSoundEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled)
      ?? Self.default.notificationSoundEnabled
    systemNotificationsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled)
      ?? Self.default.systemNotificationsEnabled
    moveNotifiedWorktreeToTop =
      try container.decodeIfPresent(Bool.self, forKey: .moveNotifiedWorktreeToTop)
      ?? Self.default.moveNotifiedWorktreeToTop
    commandFinishedNotificationEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .commandFinishedNotificationEnabled)
      ?? Self.default.commandFinishedNotificationEnabled
    commandFinishedNotificationThreshold =
      try container.decodeIfPresent(Int.self, forKey: .commandFinishedNotificationThreshold)
      ?? Self.default.commandFinishedNotificationThreshold
    analyticsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .analyticsEnabled)
      ?? Self.default.analyticsEnabled
    crashReportsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .crashReportsEnabled)
      ?? Self.default.crashReportsEnabled
    githubIntegrationEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .githubIntegrationEnabled)
      ?? Self.default.githubIntegrationEnabled
    deleteBranchOnDeleteWorktree =
      try container.decodeIfPresent(Bool.self, forKey: .deleteBranchOnDeleteWorktree)
      ?? Self.default.deleteBranchOnDeleteWorktree
    if let decoded = try container.decodeIfPresent(MergedWorktreeAction.self, forKey: .mergedWorktreeAction) {
      mergedWorktreeAction = decoded
    } else if let legacyBool = try container.decodeIfPresent(
      Bool.self, forKey: .automaticallyArchiveMergedWorktrees
    ) {
      mergedWorktreeAction = legacyBool ? .archive : nil
    } else {
      mergedWorktreeAction = Self.default.mergedWorktreeAction
    }
    promptForWorktreeCreation =
      try container.decodeIfPresent(Bool.self, forKey: .promptForWorktreeCreation)
      ?? Self.default.promptForWorktreeCreation
    fetchOriginBeforeWorktreeCreation =
      try container.decodeIfPresent(Bool.self, forKey: .fetchOriginBeforeWorktreeCreation)
      ?? Self.default.fetchOriginBeforeWorktreeCreation
    defaultWorktreeBaseDirectoryPath =
      try container.decodeIfPresent(String.self, forKey: .defaultWorktreeBaseDirectoryPath)
      ?? Self.default.defaultWorktreeBaseDirectoryPath
    copyIgnoredOnWorktreeCreate =
      try container.decodeIfPresent(Bool.self, forKey: .copyIgnoredOnWorktreeCreate)
      ?? Self.default.copyIgnoredOnWorktreeCreate
    copyUntrackedOnWorktreeCreate =
      try container.decodeIfPresent(Bool.self, forKey: .copyUntrackedOnWorktreeCreate)
      ?? Self.default.copyUntrackedOnWorktreeCreate
    pullRequestMergeStrategy =
      try container.decodeIfPresent(PullRequestMergeStrategy.self, forKey: .pullRequestMergeStrategy)
      ?? Self.default.pullRequestMergeStrategy
    restoreTerminalLayoutOnLaunch =
      try container.decodeIfPresent(Bool.self, forKey: .restoreTerminalLayoutOnLaunch)
      ?? Self.default.restoreTerminalLayoutOnLaunch
    if let rawAutoDelete = try container.decodeIfPresent(Int.self, forKey: .archivedAutoDeletePeriod) {
      archivedAutoDeletePeriod = AutoDeletePeriod(rawValue: rawAutoDelete)
    } else {
      archivedAutoDeletePeriod = Self.default.archivedAutoDeletePeriod
    }
    terminalFontSize =
      try container.decodeIfPresent(Float32.self, forKey: .terminalFontSize)
      ?? Self.default.terminalFontSize
    keybindingUserOverrides =
      try container.decodeIfPresent(KeybindingUserOverrideStore.self, forKey: .keybindingUserOverrides)
      ?? Self.default.keybindingUserOverrides
    defaultViewMode =
      try container.decodeIfPresent(DefaultViewMode.self, forKey: .defaultViewMode)
      ?? Self.default.defaultViewMode
  }
}
