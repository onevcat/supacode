import Foundation
import Testing

@testable import supacode

struct SettingsStorageTests {
  @Test func loadWritesDefaultsWhenMissing() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    let storage = SettingsStorage(settingsURL: settingsURL)

    let settings = await storage.load()

    #expect(settings == .default)
    #expect(FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)))

    let data = try Data(contentsOf: settingsURL)
    let decoded = try JSONDecoder().decode(SettingsFile.self, from: data)
    #expect(decoded == .default)
  }

  @Test func saveAndReload() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    let storage = SettingsStorage(settingsURL: settingsURL)

    var settings = await storage.load()
    settings.global.appearanceMode = .dark
    settings.repositoryRoots = ["/tmp/repo-a", "/tmp/repo-b"]
    settings.pinnedWorktreeIDs = ["/tmp/repo-a/wt-1"]
    await storage.save(settings)

    let reloaded = await SettingsStorage(settingsURL: settingsURL).load()
    #expect(reloaded.global.appearanceMode == .dark)
    #expect(reloaded.repositoryRoots == ["/tmp/repo-a", "/tmp/repo-b"])
    #expect(reloaded.pinnedWorktreeIDs == ["/tmp/repo-a/wt-1"])
  }

  @Test func invalidJSONResetsToDefaults() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: settingsURL)

    let storage = SettingsStorage(settingsURL: settingsURL)
    let settings = await storage.load()

    #expect(settings == .default)

    let data = try Data(contentsOf: settingsURL)
    let decoded = try JSONDecoder().decode(SettingsFile.self, from: data)
    #expect(decoded == .default)
  }

  @Test func migratesOldSettingsWithoutInAppNotificationsEnabled() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let oldSettings = """
      {
        "global": {
          "appearanceMode": "dark",
          "updatesAutomaticallyCheckForUpdates": false,
          "updatesAutomaticallyDownloadUpdates": true
        },
        "repositories": {}
      }
      """
    try Data(oldSettings.utf8).write(to: settingsURL)

    let storage = SettingsStorage(settingsURL: settingsURL)
    let settings = await storage.load()

    #expect(settings.global.appearanceMode == .dark)
    #expect(settings.global.updatesAutomaticallyCheckForUpdates == false)
    #expect(settings.global.updatesAutomaticallyDownloadUpdates == true)
    #expect(settings.global.inAppNotificationsEnabled == true)
    #expect(settings.repositoryRoots.isEmpty)
    #expect(settings.pinnedWorktreeIDs.isEmpty)
  }

  @Test func migratesRepositoryDataFromUserDefaults() async throws {
    let userDefaults = UserDefaults.standard
    let rootsKey = "repositories.roots"
    let pinnedKey = "repositories.worktrees.pinned"
    defer {
      userDefaults.removeObject(forKey: rootsKey)
      userDefaults.removeObject(forKey: pinnedKey)
    }
    let roots = ["/tmp/repo-a", "/tmp/repo-b"]
    let pinned = ["/tmp/repo-a/wt-1"]
    userDefaults.set(try JSONEncoder().encode(roots), forKey: rootsKey)
    userDefaults.set(try JSONEncoder().encode(pinned), forKey: pinnedKey)

    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    let storage = SettingsStorage(settingsURL: settingsURL)

    let settings = await storage.load()

    #expect(settings.repositoryRoots == roots)
    #expect(settings.pinnedWorktreeIDs == pinned)
    #expect(userDefaults.data(forKey: rootsKey) == nil)
    #expect(userDefaults.data(forKey: pinnedKey) == nil)
  }

  @Test func updatePreservesUnrelatedSettings() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let settingsURL = root.appending(path: "settings.json")
    let storage = SettingsStorage(settingsURL: settingsURL)
    var settings = SettingsFile.default
    settings.global.appearanceMode = .dark
    var repositorySettings = RepositorySettings.default
    repositorySettings.runScript = "echo hello"
    repositorySettings.openActionID = OpenWorktreeAction.ghostty.settingsID
    settings.repositories["/tmp/repo"] = repositorySettings
    await storage.save(settings)

    await storage.update { updated in
      updated.repositoryRoots = ["/tmp/repo"]
      updated.pinnedWorktreeIDs = ["/tmp/repo/wt-1"]
    }

    let reloaded = await storage.load()
    #expect(reloaded.global.appearanceMode == .dark)
    #expect(reloaded.repositories["/tmp/repo"] == settings.repositories["/tmp/repo"])
    #expect(reloaded.repositoryRoots == ["/tmp/repo"])
    #expect(reloaded.pinnedWorktreeIDs == ["/tmp/repo/wt-1"])
  }

  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
