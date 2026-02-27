import Foundation

nonisolated enum SupacodePaths {
  static var baseDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".supacode", directoryHint: .isDirectory)
  }

  static var repositorySettingsDirectory: URL {
    baseDirectory.appending(path: "repo", directoryHint: .isDirectory)
  }

  static var reposDirectory: URL {
    baseDirectory.appending(path: "repos", directoryHint: .isDirectory)
  }

  static func repositoryDirectory(for rootURL: URL) -> URL {
    let name = repositoryDirectoryName(for: rootURL)
    return reposDirectory.appending(path: name, directoryHint: .isDirectory)
  }

  static var settingsURL: URL {
    baseDirectory.appending(path: "settings.json", directoryHint: .notDirectory)
  }

  static func repositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL)
      .appending(path: "supacode.json", directoryHint: .notDirectory)
  }

  static func onevcatRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL)
      .appending(path: "supacode.onevcat.json", directoryHint: .notDirectory)
  }

  static func legacyRepositorySettingsURL(for rootURL: URL) -> URL {
    rootURL.standardizedFileURL.appending(path: "supacode.json", directoryHint: .notDirectory)
  }

  static func legacyOnevcatRepositorySettingsURL(for rootURL: URL) -> URL {
    rootURL.standardizedFileURL.appending(path: "supacode.onevcat.json", directoryHint: .notDirectory)
  }

  private static func repositorySettingsDirectory(for rootURL: URL) -> URL {
    let name = repositorySettingsDirectoryName(for: rootURL)
    return repositorySettingsDirectory.appending(path: name, directoryHint: .isDirectory)
  }

  private static func repositoryDirectoryName(for rootURL: URL) -> String {
    let repoName = rootURL.lastPathComponent
    if repoName.isEmpty || repoName == ".bare" || repoName == ".git" {
      let path = rootURL.standardizedFileURL.path(percentEncoded: false)
      let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if trimmed.isEmpty {
        return "_"
      }
      return trimmed.replacing("/", with: "_")
    }
    return repoName
  }

  private static func repositorySettingsDirectoryName(for rootURL: URL) -> String {
    let repoName = rootURL.standardizedFileURL.lastPathComponent
    if repoName.isEmpty || repoName == "/" {
      return "_"
    }
    return repoName
  }
}
