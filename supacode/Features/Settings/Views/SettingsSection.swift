import Foundation

enum SettingsSection: Hashable {
  case agents
  case chat
  case appearance
  case notifications
  case updates
  case github
  case repository(Repository.ID)
}
