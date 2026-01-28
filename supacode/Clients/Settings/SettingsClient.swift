import ComposableArchitecture
import Foundation

struct SettingsClient {
  var load: @Sendable () async -> GlobalSettings
  var save: @Sendable (GlobalSettings) async -> Void
}

extension SettingsClient: DependencyKey {
  static let liveValue = SettingsClient(
    load: {
      await SettingsStorage.shared.load().global
    },
    save: { settings in
      await SettingsStorage.shared.update { fileSettings in
        fileSettings.global = settings
      }
    }
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
