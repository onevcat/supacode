import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeRowsView: View {
  let repository: Repository
  let isExpanded: Bool
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(\.colorScheme) private var colorScheme
  @State private var draggingWorktreeIDs: Set<Worktree.ID> = []

  var body: some View {
    if isExpanded {
      let state = store.state
      let sections = state.worktreeRowSections(in: repository)
      let isRepositoryRemoving = state.isRemovingRepository(repository)
      let showShortcutHints = commandKeyObserver.isPressed
      let allRows = showShortcutHints ? state.orderedWorktreeRows() : []
      let shortcutIndexByID = Dictionary(
        uniqueKeysWithValues: allRows.enumerated().map { ($0.element.id, $0.offset) }
      )
      let rowIDs = sections.allRows.map(\.id)
      Group {
        if let row = sections.main {
          let shortcutHint =
            showShortcutHints ? worktreeShortcutHint(for: shortcutIndexByID[row.id]) : nil
          rowView(
            row,
            isRepositoryRemoving: isRepositoryRemoving,
            moveDisabled: true,
            shortcutHint: shortcutHint
          )
        }
        ForEach(sections.pinned) { row in
          let shortcutHint =
            showShortcutHints ? worktreeShortcutHint(for: shortcutIndexByID[row.id]) : nil
          rowView(
            row,
            isRepositoryRemoving: isRepositoryRemoving,
            moveDisabled: isRepositoryRemoving || row.isDeleting,
            shortcutHint: shortcutHint
          )
        }
        .onMove { offsets, destination in
          store.send(.pinnedWorktreesMoved(repositoryID: repository.id, offsets, destination))
        }
        ForEach(sections.pending) { row in
          let shortcutHint =
            showShortcutHints ? worktreeShortcutHint(for: shortcutIndexByID[row.id]) : nil
          rowView(
            row,
            isRepositoryRemoving: isRepositoryRemoving,
            moveDisabled: true,
            shortcutHint: shortcutHint
          )
        }
        ForEach(sections.unpinned) { row in
          let shortcutHint =
            showShortcutHints ? worktreeShortcutHint(for: shortcutIndexByID[row.id]) : nil
          rowView(
            row,
            isRepositoryRemoving: isRepositoryRemoving,
            moveDisabled: isRepositoryRemoving || row.isDeleting,
            shortcutHint: shortcutHint
          )
        }
        .onMove { offsets, destination in
          store.send(.unpinnedWorktreesMoved(repositoryID: repository.id, offsets, destination))
        }
      }
      .animation(.easeOut(duration: 0.2), value: rowIDs)
    }
  }

  @ViewBuilder
  private func rowView(
    _ row: WorktreeRowModel,
    isRepositoryRemoving: Bool,
    moveDisabled: Bool,
    shortcutHint: String?
  ) -> some View {
    let taskStatus = terminalManager.focusedTaskStatus(for: row.id)
    let isRunScriptRunning = terminalManager.isRunScriptRunning(for: row.id)
    let isSelected = row.id == store.state.selectedWorktreeID
    let showsNotificationIndicator = !isSelected && terminalManager.hasUnseenNotifications(for: row.id)
    let displayName = row.isDeleting ? "\(row.name) (deleting...)" : row.name
    let archiveShortcut = KeyboardShortcut(.delete, modifiers: .command).display
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    let archiveAction: (() -> Void)? =
      row.isRemovable && !row.isMainWorktree && !isRepositoryRemoving
      ? { store.send(.requestArchiveWorktree(row.id, repository.id)) }
      : nil
    Group {
      if row.isRemovable, let worktree = store.state.worktree(for: row.id), !isRepositoryRemoving {
        WorktreeRow(
          name: displayName,
          info: row.info,
          showsPullRequestInfo: !draggingWorktreeIDs.contains(row.id),
          isPinned: row.isPinned,
          isMainWorktree: row.isMainWorktree,
          isLoading: row.isPending || row.isDeleting,
          taskStatus: taskStatus,
          isRunScriptRunning: isRunScriptRunning,
          showsNotificationIndicator: showsNotificationIndicator,
          shortcutHint: shortcutHint,
          archiveAction: archiveAction
        )
        .tag(SidebarSelection.worktree(row.id))
        .typeSelectEquivalent("")
        .listRowInsets(EdgeInsets())
        .transition(.opacity)
        .moveDisabled(moveDisabled)
        .contextMenu {
          if !row.isMainWorktree {
            if row.isPinned {
              Button("Unpin") {
                store.send(.unpinWorktree(worktree.id))
              }
              .help("Unpin")
            } else {
              Button("Pin to top") {
                store.send(.pinWorktree(worktree.id))
              }
              .help("Pin to top")
            }
          }
          Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.workingDirectory.path, forType: .string)
          }
          Button("Archive Worktree (\(archiveShortcut))") {
            store.send(.requestArchiveWorktree(worktree.id, repository.id))
          }
          .help(
            row.isMainWorktree
              ? "Main worktree can't be archived"
              : "Archive Worktree (\(archiveShortcut))"
          )
          .disabled(row.isMainWorktree)
          Button("Delete Worktree (\(deleteShortcut))", role: .destructive) {
            store.send(.requestDeleteWorktree(worktree.id, repository.id))
          }
          .help(
            row.isMainWorktree
              ? "Main worktree can't be deleted"
              : "Delete Worktree (\(deleteShortcut))"
          )
          .disabled(row.isMainWorktree)
        }
      } else {
        WorktreeRow(
          name: displayName,
          info: row.info,
          showsPullRequestInfo: !draggingWorktreeIDs.contains(row.id),
          isPinned: row.isPinned,
          isMainWorktree: row.isMainWorktree,
          isLoading: row.isPending || row.isDeleting,
          taskStatus: taskStatus,
          isRunScriptRunning: isRunScriptRunning,
          showsNotificationIndicator: showsNotificationIndicator,
          shortcutHint: shortcutHint,
          archiveAction: archiveAction
        )
        .tag(SidebarSelection.worktree(row.id))
        .typeSelectEquivalent("")
        .listRowInsets(EdgeInsets())
        .transition(.opacity)
        .moveDisabled(moveDisabled)
        .disabled(isRepositoryRemoving)
      }
    }
    .contentShape(.dragPreview, .rect)
    .environment(\.colorScheme, colorScheme)
    .preferredColorScheme(colorScheme)
    .onDragSessionUpdated { session in
      let draggedIDs = Set(session.draggedItemIDs(for: Worktree.ID.self))
      if case .ended = session.phase {
        if !draggingWorktreeIDs.isEmpty {
          draggingWorktreeIDs = []
        }
        return
      }
      if case .dataTransferCompleted = session.phase {
        if !draggingWorktreeIDs.isEmpty {
          draggingWorktreeIDs = []
        }
        return
      }
      if draggedIDs != draggingWorktreeIDs {
        draggingWorktreeIDs = draggedIDs
      }
    }
  }

  private func worktreeShortcutHint(for index: Int?) -> String? {
    guard let index, AppShortcuts.worktreeSelection.indices.contains(index) else { return nil }
    return AppShortcuts.worktreeSelection[index].display
  }
}
