nonisolated struct GlobalSettings: Codable, Equatable, Sendable {
  var appearanceMode: AppearanceMode
  var confirmBeforeQuit: Bool
  var updatesAutomaticallyCheckForUpdates: Bool
  var updatesAutomaticallyDownloadUpdates: Bool
  var inAppNotificationsEnabled: Bool
  var dockBadgeEnabled: Bool
  var notificationSoundEnabled: Bool
  var githubIntegrationEnabled: Bool
  var deleteBranchOnDeleteWorktree: Bool
  var automaticallyArchiveMergedWorktrees: Bool

  static let `default` = GlobalSettings(
    appearanceMode: .dark,
    confirmBeforeQuit: true,
    updatesAutomaticallyCheckForUpdates: true,
    updatesAutomaticallyDownloadUpdates: false,
    inAppNotificationsEnabled: true,
    dockBadgeEnabled: true,
    notificationSoundEnabled: true,
    githubIntegrationEnabled: true,
    deleteBranchOnDeleteWorktree: true,
    automaticallyArchiveMergedWorktrees: false
  )

  init(
    appearanceMode: AppearanceMode,
    confirmBeforeQuit: Bool,
    updatesAutomaticallyCheckForUpdates: Bool,
    updatesAutomaticallyDownloadUpdates: Bool,
    inAppNotificationsEnabled: Bool,
    dockBadgeEnabled: Bool,
    notificationSoundEnabled: Bool,
    githubIntegrationEnabled: Bool,
    deleteBranchOnDeleteWorktree: Bool,
    automaticallyArchiveMergedWorktrees: Bool
  ) {
    self.appearanceMode = appearanceMode
    self.confirmBeforeQuit = confirmBeforeQuit
    self.updatesAutomaticallyCheckForUpdates = updatesAutomaticallyCheckForUpdates
    self.updatesAutomaticallyDownloadUpdates = updatesAutomaticallyDownloadUpdates
    self.inAppNotificationsEnabled = inAppNotificationsEnabled
    self.dockBadgeEnabled = dockBadgeEnabled
    self.notificationSoundEnabled = notificationSoundEnabled
    self.githubIntegrationEnabled = githubIntegrationEnabled
    self.deleteBranchOnDeleteWorktree = deleteBranchOnDeleteWorktree
    self.automaticallyArchiveMergedWorktrees = automaticallyArchiveMergedWorktrees
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
    confirmBeforeQuit =
      try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuit)
      ?? Self.default.confirmBeforeQuit
    updatesAutomaticallyCheckForUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyCheckForUpdates)
    updatesAutomaticallyDownloadUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyDownloadUpdates)
    inAppNotificationsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .inAppNotificationsEnabled)
      ?? Self.default.inAppNotificationsEnabled
    dockBadgeEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .dockBadgeEnabled)
      ?? Self.default.dockBadgeEnabled
    notificationSoundEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled)
      ?? Self.default.notificationSoundEnabled
    githubIntegrationEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .githubIntegrationEnabled)
      ?? Self.default.githubIntegrationEnabled
    deleteBranchOnDeleteWorktree =
      try container.decodeIfPresent(Bool.self, forKey: .deleteBranchOnDeleteWorktree)
      ?? Self.default.deleteBranchOnDeleteWorktree
    automaticallyArchiveMergedWorktrees =
      try container.decodeIfPresent(Bool.self, forKey: .automaticallyArchiveMergedWorktrees)
      ?? Self.default.automaticallyArchiveMergedWorktrees
  }
}
