import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
  private let userDefaults: UserDefaults
  private let appearanceKey = "settings.appearanceMode"

  var appearanceMode: AppearanceMode {
    didSet {
      userDefaults.set(appearanceMode.rawValue, forKey: appearanceKey)
    }
  }

  var preferredColorScheme: ColorScheme? {
    appearanceMode.colorScheme
  }

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    let rawValue = userDefaults.string(forKey: appearanceKey)
    appearanceMode = AppearanceMode(rawValue: rawValue ?? AppearanceMode.system.rawValue) ?? .system
  }
}
