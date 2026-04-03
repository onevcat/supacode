import Foundation

struct ListRuntimeSnapshot: Sendable {
  struct Worktree: Sendable {
    let id: String
    let name: String
    let path: String
    let rootPath: String
    let kind: ListCommandWorktree.Kind
    let taskStatus: ListCommandTask.Status?
    let tabs: [Tab]
  }

  struct Tab: Sendable {
    let id: UUID
    let title: String
    let selected: Bool
    let focusedPaneID: UUID?
    let panes: [Pane]
  }

  struct Pane: Sendable {
    let id: UUID
    let title: String
    let cwd: String?
  }

  let worktrees: [Worktree]
  let focusedWorktreeID: String?
}

final class ListCommandHandler: CommandHandler {
  typealias SnapshotProvider = @MainActor () throws -> ListRuntimeSnapshot

  private let snapshotProvider: SnapshotProvider

  init(snapshotProvider: @escaping SnapshotProvider) {
    self.snapshotProvider = snapshotProvider
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope _: CommandEnvelope) async -> CommandResponse {
    do {
      let snapshot = try snapshotProvider()
      let payload = makePayload(from: snapshot)
      return try CommandResponse(
        ok: true,
        command: "list",
        schemaVersion: "prowl.cli.list.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return CommandResponse(
        ok: false,
        command: "list",
        schemaVersion: "prowl.cli.list.v1",
        error: CommandError(
          code: CLIErrorCode.listFailed,
          message: "Failed to list panes."
        )
      )
    }
  }

  private func makePayload(from snapshot: ListRuntimeSnapshot) -> ListCommandPayload {
    var items: [ListCommandItem] = []
    var didAssignFocusedPane = false

    for worktree in snapshot.worktrees {
      for tab in worktree.tabs {
        for pane in tab.panes {
          let isFocused =
            !didAssignFocusedPane
            && worktree.id == snapshot.focusedWorktreeID
            && tab.selected
            && tab.focusedPaneID == pane.id

          if isFocused {
            didAssignFocusedPane = true
          }

          items.append(
            ListCommandItem(
              worktree: ListCommandWorktree(
                id: worktree.id,
                name: worktree.name,
                path: worktree.path,
                rootPath: worktree.rootPath,
                kind: worktree.kind
              ),
              tab: ListCommandTab(
                id: tab.id.uuidString,
                title: tab.title,
                selected: tab.selected
              ),
              pane: ListCommandPane(
                id: pane.id.uuidString,
                title: pane.title,
                cwd: pane.cwd,
                focused: isFocused
              ),
              task: ListCommandTask(status: worktree.taskStatus)
            )
          )
        }
      }
    }

    return ListCommandPayload(count: items.count, items: items)
  }
}
