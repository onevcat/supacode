import ComposableArchitecture
import Foundation

struct RepositorySettingsClient {
  var load: @Sendable (URL) async -> RepositorySettings
  var save: @Sendable (_ settings: RepositorySettings, _ rootURL: URL) async -> Void
}

extension RepositorySettingsClient: DependencyKey {
  static let liveValue = RepositorySettingsClient(
    load: { await RepositorySettingsStorage().load(for: $0) },
    save: { settings, url in
      await RepositorySettingsStorage().save(settings, for: url)
    }
  )
  static let testValue = RepositorySettingsClient(
    load: { _ in .default },
    save: { _, _ in }
  )
}

extension DependencyValues {
  var repositorySettingsClient: RepositorySettingsClient {
    get { self[RepositorySettingsClient.self] }
    set { self[RepositorySettingsClient.self] = newValue }
  }
}
