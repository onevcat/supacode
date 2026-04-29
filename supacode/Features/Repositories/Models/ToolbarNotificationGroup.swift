import Foundation

struct ToolbarNotificationRepositoryGroup: Identifiable, Equatable {
  let id: Repository.ID
  let name: String
  let worktrees: [ToolbarNotificationWorktreeGroup]

  var notificationCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + worktree.notifications.count
    }
  }

  var unseenWorktreeCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + (worktree.hasUnseenNotifications ? 1 : 0)
    }
  }
}

struct ToolbarNotificationWorktreeGroup: Identifiable, Equatable {
  let id: Worktree.ID
  let name: String
  let notifications: [WorktreeTerminalNotification]
  let hasUnseenNotifications: Bool
}

extension RepositoriesFeature.State {
  /// `customTitles` is an optional per-repo display-name dictionary;
  /// when an entry exists the group's `name` uses it instead of
  /// `repository.name`. Defaults to empty for legacy callers/tests.
  func toolbarNotificationGroups(
    terminalManager: WorktreeTerminalManager,
    customTitles: [Repository.ID: String] = [:]
  ) -> [ToolbarNotificationRepositoryGroup] {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    var groups: [ToolbarNotificationRepositoryGroup] = []

    for repositoryID in orderedRepositoryIDs() {
      guard let repository = repositoriesByID[repositoryID] else {
        continue
      }

      let worktreeGroups: [ToolbarNotificationWorktreeGroup] =
        orderedWorktrees(in: repository).compactMap { worktree -> ToolbarNotificationWorktreeGroup? in
          guard let state = terminalManager.stateIfExists(for: worktree.id), !state.notifications.isEmpty else {
            return nil
          }
          return ToolbarNotificationWorktreeGroup(
            id: worktree.id,
            name: worktree.name,
            notifications: state.notifications,
            hasUnseenNotifications: terminalManager.hasUnseenNotifications(for: worktree.id)
          )
        }

      if !worktreeGroups.isEmpty {
        groups.append(
          ToolbarNotificationRepositoryGroup(
            id: repository.id,
            name: customTitles[repository.id] ?? repository.name,
            worktrees: worktreeGroups
          )
        )
      }
    }

    return groups
  }
}
