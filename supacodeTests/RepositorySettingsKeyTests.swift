import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

struct RepositorySettingsKeyTests {
  @Test func encodingOmitsNilWorktreeBaseRef() throws {
    let data = try JSONEncoder().encode(RepositorySettings.default)
    let json = String(bytes: data, encoding: .utf8) ?? ""

    #expect(!json.contains("worktreeBaseRef"))
  }

  @Test(.dependencies) func loadCreatesDefaultAndPersists() throws {
    let storage = SettingsTestStorage()
    let rootURL = URL(fileURLWithPath: "/tmp/repo")

    let settings = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.repositorySettings(rootURL)) var repositorySettings: RepositorySettings
      return repositorySettings
    }

    #expect(settings == RepositorySettings.default)

    let saved: SettingsFile = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.settingsFile) var settings: SettingsFile
      return settings
    }

    #expect(
      saved.repositories[rootURL.path(percentEncoded: false)] == RepositorySettings.default
    )
  }

  @Test(.dependencies) func saveOverwritesExistingSettings() throws {
    let storage = SettingsTestStorage()
    let rootURL = URL(fileURLWithPath: "/tmp/repo")

    var settings = RepositorySettings.default
    settings.runScript = "echo updated"
    withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.repositorySettings(rootURL)) var repositorySettings: RepositorySettings
      $repositorySettings.withLock {
        $0 = settings
      }
    }

    let reloaded: SettingsFile = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.settingsFile) var settings: SettingsFile
      return settings
    }

    #expect(reloaded.repositories[rootURL.path(percentEncoded: false)] == settings)
  }

  @Test func decodeMissingArchiveScriptDefaultsToEmpty() throws {
    let data = Data(
      """
      {
        "setupScript": "echo setup",
        "runScript": "echo run",
        "openActionID": "automatic"
      }
      """.utf8
    )
    let settings = try JSONDecoder().decode(RepositorySettings.self, from: data)

    #expect(settings.archiveScript.isEmpty)
  }
}
