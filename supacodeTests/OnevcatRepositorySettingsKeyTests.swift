import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

struct OnevcatRepositorySettingsKeyTests {
  @Test(.dependencies) func loadMissingFileReturnsDefaultAndCreatesLocalFile() throws {
    let localStorage = RepositoryLocalSettingsTestStorage()
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let localURL = SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)

    let loaded = withDependencies {
      $0.repositoryLocalSettingsStorage = localStorage.storage
    } operation: {
      @Shared(.onevcatRepositorySettings(rootURL)) var settings: OnevcatRepositorySettings
      return settings
    }

    #expect(loaded == .default)

    let localData = try #require(localStorage.data(at: localURL))
    let decoded = try JSONDecoder().decode(OnevcatRepositorySettings.self, from: localData)
    #expect(decoded == .default)
  }

  @Test(.dependencies) func savePersistsCustomCommandsToOnevcatFile() throws {
    let localStorage = RepositoryLocalSettingsTestStorage()
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let localURL = SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)

    let customSettings = OnevcatRepositorySettings(
      customCommands: [
        OnevcatCustomCommand(
          title: "Test",
          systemImage: "checkmark.circle",
          command: "swift test",
          execution: .shellScript,
          shortcut: OnevcatCustomShortcut(
            key: "u",
            modifiers: OnevcatCustomShortcutModifiers(command: true)
          )
        ),
      ]
    )

    withDependencies {
      $0.repositoryLocalSettingsStorage = localStorage.storage
    } operation: {
      @Shared(.onevcatRepositorySettings(rootURL)) var settings: OnevcatRepositorySettings
      $settings.withLock {
        $0 = customSettings
      }
    }

    let localData = try #require(localStorage.data(at: localURL))
    let decoded = try JSONDecoder().decode(OnevcatRepositorySettings.self, from: localData)
    #expect(decoded == customSettings)
  }

  @Test(.dependencies) func loadMigratesLegacyRepositoryRootOnevcatFile() throws {
    let localStorage = RepositoryLocalSettingsTestStorage()
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let localURL = SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)
    let legacyURL = SupacodePaths.legacyOnevcatRepositorySettingsURL(for: rootURL)

    let customSettings = OnevcatRepositorySettings(
      customCommands: [
        OnevcatCustomCommand(
          title: "Legacy",
          systemImage: "terminal",
          command: "echo legacy",
          execution: .shellScript,
          shortcut: OnevcatCustomShortcut(
            key: "u",
            modifiers: OnevcatCustomShortcutModifiers(command: true)
          )
        ),
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try localStorage.save(try encoder.encode(customSettings), at: legacyURL)

    let loaded = withDependencies {
      $0.repositoryLocalSettingsStorage = localStorage.storage
    } operation: {
      @Shared(.onevcatRepositorySettings(rootURL)) var settings: OnevcatRepositorySettings
      return settings
    }

    #expect(loaded == customSettings)

    let localData = try #require(localStorage.data(at: localURL))
    let decoded = try JSONDecoder().decode(OnevcatRepositorySettings.self, from: localData)
    #expect(decoded == customSettings)
  }
}
