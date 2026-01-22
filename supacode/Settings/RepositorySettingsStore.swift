import Foundation

nonisolated struct RepositorySettingsStore {
  func load(for rootURL: URL) -> RepositorySettings {
    let settingsURL = settingsURL(for: rootURL)
    if let data = try? Data(contentsOf: settingsURL),
      let settings = try? JSONDecoder().decode(RepositorySettings.self, from: data)
    {
      return settings
    }
    let defaults = RepositorySettings.default
    save(defaults, for: rootURL)
    return defaults
  }

  func save(_ settings: RepositorySettings, for rootURL: URL) {
    do {
      let settingsURL = settingsURL(for: rootURL)
      let directory = settingsURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(settings)
      try data.write(to: settingsURL, options: [.atomic])
    } catch {
    }
  }

  private func settingsURL(for rootURL: URL) -> URL {
    SupacodePaths.repositoryDirectory(for: rootURL)
      .appending(path: "settings.json", directoryHint: .notDirectory)
  }
}
