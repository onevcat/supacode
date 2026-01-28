import Foundation

nonisolated struct RepositorySettingsStorage {
  func load(for rootURL: URL) async -> RepositorySettings {
    let repositoryID = repositoryID(for: rootURL)
    return await SettingsStorage.shared.update { fileSettings in
      if let settings = fileSettings.repositories[repositoryID] {
        return settings
      }
      let defaults = RepositorySettings.default
      fileSettings.repositories[repositoryID] = defaults
      return defaults
    }
  }

  func save(_ settings: RepositorySettings, for rootURL: URL) async {
    let repositoryID = repositoryID(for: rootURL)
    await SettingsStorage.shared.update { fileSettings in
      fileSettings.repositories[repositoryID] = settings
    }
  }

  private func repositoryID(for rootURL: URL) -> String {
    rootURL.standardizedFileURL.path(percentEncoded: false)
  }
}
