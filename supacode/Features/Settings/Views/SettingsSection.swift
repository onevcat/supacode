import Foundation

enum SettingsSection: Hashable {
  case general
  case notifications
  case updates
  case github
  case repository(Repository.ID)
}
