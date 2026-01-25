import ComposableArchitecture
import Foundation

struct SettingsClient {
  var load: @Sendable () -> GlobalSettings
  var save: @Sendable (GlobalSettings) -> Void
}

extension SettingsClient: DependencyKey {
  static let liveValue = SettingsClient(
    load: { SettingsStorage().load() },
    save: { SettingsStorage().save($0) }
  )
  static let testValue = SettingsClient(
    load: { .default },
    save: { _ in }
  )
}

extension DependencyValues {
  var settingsClient: SettingsClient {
    get { self[SettingsClient.self] }
    set { self[SettingsClient.self] = newValue }
  }
}
