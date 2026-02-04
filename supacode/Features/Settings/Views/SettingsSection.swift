import Foundation

enum SettingsSection: Hashable {
  case general
  case notifications
  case worktree
  case updates
  case advanced
  case github
  case repository(Repository.ID)
}
