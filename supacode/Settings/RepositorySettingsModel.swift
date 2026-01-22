import Foundation
import Observation

@MainActor
@Observable
final class RepositorySettingsModel {
  private let store: RepositorySettingsStore
  private let rootURL: URL
  private var settings: RepositorySettings

  var startupCommand: String {
    get {
      settings.startupCommand
    }
    set {
      settings.startupCommand = newValue
      store.save(settings, for: rootURL)
    }
  }

  init(rootURL: URL, store: RepositorySettingsStore = RepositorySettingsStore()) {
    self.rootURL = rootURL
    self.store = store
    settings = store.load(for: rootURL)
  }
}
