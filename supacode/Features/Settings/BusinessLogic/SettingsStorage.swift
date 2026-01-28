import Foundation

actor SettingsStorage {
  static let shared = SettingsStorage()
  let settingsURL: URL

  init(settingsURL: URL = SupacodePaths.settingsURL) {
    self.settingsURL = settingsURL
  }

  func load() -> SettingsFile {
    loadLocked()
  }

  func save(_ settings: SettingsFile) {
    saveLocked(settings)
  }

  func update<T: Sendable>(_ transform: @Sendable (inout SettingsFile) -> T) -> T {
    var settings = loadLocked()
    let result = transform(&settings)
    saveLocked(settings)
    return result
  }

  private func loadLocked() -> SettingsFile {
    var settings: SettingsFile
    var shouldSave = false
    if let data = try? Data(contentsOf: settingsURL),
      let decoded = try? JSONDecoder().decode(SettingsFile.self, from: data)
    {
      settings = decoded
    } else {
      settings = SettingsFile.default
      shouldSave = true
    }
    if migrateFromUserDefaults(into: &settings) {
      shouldSave = true
    }
    if shouldSave {
      saveLocked(settings)
    }
    return settings
  }

  private func saveLocked(_ settings: SettingsFile) {
    do {
      let directory = settingsURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(settings)
      try data.write(to: settingsURL, options: [.atomic])
    } catch {
    }
  }

  private func migrateFromUserDefaults(into settings: inout SettingsFile) -> Bool {
    let userDefaults = UserDefaults.standard
    let rootsKey = "repositories.roots"
    let pinnedKey = "repositories.worktrees.pinned"
    var didMigrate = false
    if settings.repositoryRoots.isEmpty,
      let data = userDefaults.data(forKey: rootsKey),
      let roots = try? JSONDecoder().decode([String].self, from: data),
      !roots.isEmpty
    {
      settings.repositoryRoots = roots
      didMigrate = true
    }
    if settings.pinnedWorktreeIDs.isEmpty,
      let data = userDefaults.data(forKey: pinnedKey),
      let ids = try? JSONDecoder().decode([Worktree.ID].self, from: data),
      !ids.isEmpty
    {
      settings.pinnedWorktreeIDs = ids
      didMigrate = true
    }
    if userDefaults.object(forKey: rootsKey) != nil {
      userDefaults.removeObject(forKey: rootsKey)
    }
    if userDefaults.object(forKey: pinnedKey) != nil {
      userDefaults.removeObject(forKey: pinnedKey)
    }
    return didMigrate
  }
}
