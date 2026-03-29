import Foundation

enum SettingsSection: Hashable {
  case general
  case notifications
  case worktree
  case sshHosts
  case updates
  case advanced
  case github
  case repository(Repository.ID)
}
