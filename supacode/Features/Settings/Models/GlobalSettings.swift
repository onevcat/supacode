nonisolated struct GlobalSettings: Codable, Equatable, Sendable {
  var appearanceMode: AppearanceMode
  var updatesAutomaticallyCheckForUpdates: Bool
  var updatesAutomaticallyDownloadUpdates: Bool
  var inAppNotificationsEnabled: Bool
  var notificationSoundEnabled: Bool

  static let `default` = GlobalSettings(
    appearanceMode: .dark,
    updatesAutomaticallyCheckForUpdates: true,
    updatesAutomaticallyDownloadUpdates: false,
    inAppNotificationsEnabled: true,
    notificationSoundEnabled: true
  )

  init(
    appearanceMode: AppearanceMode,
    updatesAutomaticallyCheckForUpdates: Bool,
    updatesAutomaticallyDownloadUpdates: Bool,
    inAppNotificationsEnabled: Bool,
    notificationSoundEnabled: Bool
  ) {
    self.appearanceMode = appearanceMode
    self.updatesAutomaticallyCheckForUpdates = updatesAutomaticallyCheckForUpdates
    self.updatesAutomaticallyDownloadUpdates = updatesAutomaticallyDownloadUpdates
    self.inAppNotificationsEnabled = inAppNotificationsEnabled
    self.notificationSoundEnabled = notificationSoundEnabled
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
    updatesAutomaticallyCheckForUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyCheckForUpdates)
    updatesAutomaticallyDownloadUpdates = try container.decode(Bool.self, forKey: .updatesAutomaticallyDownloadUpdates)
    inAppNotificationsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .inAppNotificationsEnabled)
      ?? Self.default.inAppNotificationsEnabled
    notificationSoundEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled)
      ?? Self.default.notificationSoundEnabled
  }
}
