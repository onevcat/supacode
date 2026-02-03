nonisolated struct GlobalSettings: Codable, Equatable, Sendable {
  var appearanceMode: AppearanceMode
  var confirmBeforeQuit: Bool
  var updatesAutomaticallyCheckForUpdates: Bool
  var updatesAutomaticallyDownloadUpdates: Bool
  var inAppNotificationsEnabled: Bool
  var dockBadgeEnabled: Bool
  var notificationSoundEnabled: Bool
  var githubIntegrationEnabled: Bool
  var deleteBranchOnArchive: Bool
  var sortMergedWorktreesToBottom: Bool

  static let `default` = GlobalSettings(
    appearanceMode: .dark,
    confirmBeforeQuit: true,
    updatesAutomaticallyCheckForUpdates: true,
    updatesAutomaticallyDownloadUpdates: false,
    inAppNotificationsEnabled: true,
    dockBadgeEnabled: true,
    notificationSoundEnabled: true,
    githubIntegrationEnabled: true,
    deleteBranchOnArchive: true,
    sortMergedWorktreesToBottom: true
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
    deleteBranchOnArchive: Bool,
    sortMergedWorktreesToBottom: Bool
  ) {
    self.appearanceMode = appearanceMode
    self.confirmBeforeQuit = confirmBeforeQuit
    self.updatesAutomaticallyCheckForUpdates = updatesAutomaticallyCheckForUpdates
    self.updatesAutomaticallyDownloadUpdates = updatesAutomaticallyDownloadUpdates
    self.inAppNotificationsEnabled = inAppNotificationsEnabled
    self.dockBadgeEnabled = dockBadgeEnabled
    self.notificationSoundEnabled = notificationSoundEnabled
    self.githubIntegrationEnabled = githubIntegrationEnabled
    self.deleteBranchOnArchive = deleteBranchOnArchive
    self.sortMergedWorktreesToBottom = sortMergedWorktreesToBottom
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
    deleteBranchOnArchive =
      try container.decodeIfPresent(Bool.self, forKey: .deleteBranchOnArchive)
      ?? Self.default.deleteBranchOnArchive
    sortMergedWorktreesToBottom =
      try container.decodeIfPresent(Bool.self, forKey: .sortMergedWorktreesToBottom)
      ?? Self.default.sortMergedWorktreesToBottom
  }
}
