import Dependencies
import Foundation
import Sharing

nonisolated struct OnevcatRepositorySettingsKeyID: Hashable, Sendable {
  let repositoryID: String
}

nonisolated struct OnevcatRepositorySettingsKey: SharedKey {
  let repositoryID: String
  let rootURL: URL

  init(rootURL: URL) {
    self.rootURL = rootURL.standardizedFileURL
    repositoryID = self.rootURL.path(percentEncoded: false)
  }

  var id: OnevcatRepositorySettingsKeyID {
    OnevcatRepositorySettingsKeyID(repositoryID: repositoryID)
  }

  func load(
    context: LoadContext<OnevcatRepositorySettings>,
    continuation: LoadContinuation<OnevcatRepositorySettings>
  ) {
    @Dependency(\.repositoryLocalSettingsStorage) var repositoryLocalSettingsStorage
    let settingsURL = SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)
    if let localData = try? repositoryLocalSettingsStorage.load(settingsURL) {
      let decoder = JSONDecoder()
      if let settings = try? decoder.decode(OnevcatRepositorySettings.self, from: localData) {
        continuation.resume(returning: settings.normalized())
        return
      }
      let path = settingsURL.path(percentEncoded: false)
      SupaLogger("Settings").warning(
        "Unable to decode onevcat repository settings at \(path); using defaults."
      )
    }

    let defaultSettings = (context.initialValue ?? .default).normalized()
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(defaultSettings)
      try repositoryLocalSettingsStorage.save(data, settingsURL)
    } catch {
      let path = settingsURL.path(percentEncoded: false)
      SupaLogger("Settings").warning(
        "Unable to write onevcat repository settings to \(path): \(error.localizedDescription)"
      )
    }

    continuation.resume(returning: defaultSettings)
  }

  func subscribe(
    context _: LoadContext<OnevcatRepositorySettings>,
    subscriber _: SharedSubscriber<OnevcatRepositorySettings>
  ) -> SharedSubscription {
    SharedSubscription {}
  }

  func save(
    _ value: OnevcatRepositorySettings,
    context _: SaveContext,
    continuation: SaveContinuation
  ) {
    @Dependency(\.repositoryLocalSettingsStorage) var repositoryLocalSettingsStorage
    let settingsURL = SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(value.normalized())
      try repositoryLocalSettingsStorage.save(data, settingsURL)
      continuation.resume()
    } catch {
      continuation.resume(throwing: error)
    }
  }
}

nonisolated extension SharedReaderKey where Self == OnevcatRepositorySettingsKey.Default {
  static func onevcatRepositorySettings(_ rootURL: URL) -> Self {
    Self[OnevcatRepositorySettingsKey(rootURL: rootURL), default: .default]
  }
}
