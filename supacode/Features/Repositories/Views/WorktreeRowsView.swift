import ComposableArchitecture
import SwiftUI

struct WorktreeRowsView: View {
  let repository: Repository
  let isExpanded: Bool
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    if isExpanded {
      let state = store.state
      let rows = state.worktreeRows(in: repository)
      let isRepositoryRemoving = state.isRemovingRepository(repository)
      let selectedRepositoryID = state.repositoryID(for: state.selectedWorktreeID)
      let showShortcutHints = commandKeyObserver.isPressed && selectedRepositoryID == repository.id
      ForEach(rows.enumerated(), id: \.element.id) { index, row in
        let shortcutHint = showShortcutHints ? worktreeShortcutHint(for: index) : nil
        rowView(
          row,
          isRepositoryRemoving: isRepositoryRemoving,
          shortcutHint: shortcutHint
        )
      }
    }
  }

  @ViewBuilder
  private func rowView(
    _ row: WorktreeRowModel,
    isRepositoryRemoving: Bool,
    shortcutHint: String?
  ) -> some View {
    let taskStatus = terminalManager.focusedTaskStatus(for: row.id)
    if row.isRemovable, let worktree = store.state.worktree(for: row.id), !isRepositoryRemoving {
      WorktreeRow(
        name: row.name,
        isPinned: row.isPinned,
        isMainWorktree: row.isMainWorktree,
        isLoading: row.isPending || row.isDeleting,
        taskStatus: taskStatus,
        shortcutHint: shortcutHint
      )
      .tag(SidebarSelection.worktree(row.id))
      .contextMenu {
        if row.isPinned {
          Button("Unpin") {
            store.send(.unpinWorktree(worktree.id))
          }
          .help("Unpin (no shortcut)")
        } else {
          Button("Pin to top") {
            store.send(.pinWorktree(worktree.id))
          }
          .help("Pin to top (no shortcut)")
        }
        Button("Remove") {
          store.send(.requestRemoveWorktree(worktree.id, repository.id))
        }
        .help(row.isMainWorktree ? "Main worktree can't be removed" : "Remove worktree (⌘⌫)")
        .disabled(row.isMainWorktree)
      }
    } else {
      WorktreeRow(
        name: row.name,
        isPinned: row.isPinned,
        isMainWorktree: row.isMainWorktree,
        isLoading: row.isPending || row.isDeleting,
        taskStatus: taskStatus,
        shortcutHint: shortcutHint
      )
      .tag(SidebarSelection.worktree(row.id))
      .disabled(isRepositoryRemoving)
    }
  }

  private func worktreeShortcutHint(for index: Int) -> String? {
    guard AppShortcuts.worktreeSelection.indices.contains(index) else { return nil }
    return AppShortcuts.worktreeSelection[index].display
  }
}
