import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeRowsView: View {
  let repository: Repository
  let isExpanded: Bool
  let hotkeyRows: [WorktreeRowModel]
  let selectedWorktreeIDs: Set<Worktree.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings
  @State private var draggingWorktreeIDs: Set<Worktree.ID> = []
  @State private var hoveredWorktreeID: Worktree.ID?
  @State private var targetedPinnedDropDestination: Int?
  @State private var targetedUnpinnedDropDestination: Int?

  var body: some View {
    if isExpanded {
      expandedRowsView
    }
  }

  private var expandedRowsView: some View {
    let state = store.state
    let sections = state.worktreeRowSections(in: repository)
    let isRepositoryRemoving = state.isRemovingRepository(repository)
    let isSidebarDragActive = state.isSidebarDragActive
    let showShortcutHints = commandKeyObserver.isPressed
    let allRows = showShortcutHints ? hotkeyRows : []
    let shortcutIndexByID = Dictionary(
      uniqueKeysWithValues: allRows.enumerated().map { ($0.element.id, $0.offset) }
    )
    let rowIDs = sections.allRows.map(\.id)
    return rowsGroup(
      sections: sections,
      isRepositoryRemoving: isRepositoryRemoving,
      shortcutIndexByID: shortcutIndexByID
    )
    .animation(isSidebarDragActive ? nil : .easeOut(duration: 0.2), value: rowIDs)
  }

  @ViewBuilder
  private func rowsGroup(
    sections: WorktreeRowSections,
    isRepositoryRemoving: Bool,
    shortcutIndexByID: [Worktree.ID: Int]
  ) -> some View {
    if let row = sections.main {
      rowView(
        row,
        isRepositoryRemoving: isRepositoryRemoving,
        moveDisabled: true,
        shortcutHint: worktreeShortcutHint(for: shortcutIndexByID[row.id])
      )
    }
    movableRowsGroup(
      rows: sections.pinned,
      section: .pinned,
      targetedDestination: $targetedPinnedDropDestination,
      isRepositoryRemoving: isRepositoryRemoving,
      shortcutIndexByID: shortcutIndexByID
    )
    ForEach(sections.pending) { row in
      rowView(
        row,
        isRepositoryRemoving: isRepositoryRemoving,
        moveDisabled: true,
        shortcutHint: worktreeShortcutHint(for: shortcutIndexByID[row.id])
      )
    }
    movableRowsGroup(
      rows: sections.unpinned,
      section: .unpinned,
      targetedDestination: $targetedUnpinnedDropDestination,
      isRepositoryRemoving: isRepositoryRemoving,
      shortcutIndexByID: shortcutIndexByID
    )
  }

  @ViewBuilder
  private func movableRowsGroup(
    rows: [WorktreeRowModel],
    section: SidebarWorktreeSection,
    targetedDestination: Binding<Int?>,
    isRepositoryRemoving: Bool,
    shortcutIndexByID: [Worktree.ID: Int]
  ) -> some View {
    let rowIDs = rows.map(\.id)
    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
      worktreeDropZone(
        destination: index,
        rowIDs: rowIDs,
        targetedDestination: targetedDestination,
        section: section
      )
      rowView(
        row,
        isRepositoryRemoving: isRepositoryRemoving,
        moveDisabled: isRepositoryRemoving || row.isDeleting || row.isArchiving,
        shortcutHint: worktreeShortcutHint(for: shortcutIndexByID[row.id])
      )
    }
    worktreeDropZone(
      destination: rows.count,
      rowIDs: rowIDs,
      targetedDestination: targetedDestination,
      section: section
    )
  }

  @ViewBuilder
  private func rowView(
    _ row: WorktreeRowModel,
    isRepositoryRemoving: Bool,
    moveDisabled: Bool,
    shortcutHint: String?
  ) -> some View {
    let isSidebarDragActive = store.state.isSidebarDragActive
    let showsNotificationIndicator = terminalManager.hasUnseenNotifications(for: row.id)
    let displayName =
      if row.isDeleting {
        "\(row.name) (deleting...)"
      } else if row.isArchiving {
        "\(row.name) (archiving...)"
      } else {
        row.name
      }
    let canShowRowActions = row.isRemovable && !isRepositoryRemoving && !isSidebarDragActive
    let pinAction: (() -> Void)? =
      canShowRowActions && !row.isMainWorktree
      ? { togglePin(for: row.id, isPinned: row.isPinned) }
      : nil
    let archiveAction: (() -> Void)? =
      canShowRowActions && !row.isMainWorktree
      ? { archiveWorktree(row.id) }
      : nil
    let notifications = terminalManager.stateIfExists(for: row.id)?.notifications ?? []
    let onFocusNotification: (WorktreeTerminalNotification) -> Void = { notification in
      guard let terminalState = terminalManager.stateIfExists(for: row.id) else {
        return
      }
      _ = terminalState.focusSurface(id: notification.surfaceId)
    }
    let onDiffTap: (() -> Void)? = {
      guard let worktree = store.state.worktree(for: row.id) else { return }
      DiffWindowManager.shared.show(
        worktreeURL: worktree.workingDirectory,
        branchName: worktree.name,
        resolvedKeybindings: resolvedKeybindings
      )
    }
    let onStopRunScript: (() -> Void)? =
      terminalManager.isRunScriptRunning(for: row.id)
      ? { _ = terminalManager.stateIfExists(for: row.id)?.stopRunScript() }
      : nil
    let config = WorktreeRowViewConfig(
      displayName: displayName,
      worktreeName: worktreeName(for: row),
      isHovered: !isSidebarDragActive && hoveredWorktreeID == row.id,
      showsNotificationIndicator: !isSidebarDragActive && showsNotificationIndicator,
      notifications: isSidebarDragActive ? [] : notifications,
      onFocusNotification: onFocusNotification,
      shortcutHint: shortcutHint,
      pinAction: pinAction,
      archiveAction: archiveAction,
      onDiffTap: onDiffTap,
      onStopRunScript: onStopRunScript,
      moveDisabled: moveDisabled,
    )
    let baseRow = worktreeRowView(row, config: config)
    Group {
      if row.isRemovable, let worktree = store.state.worktree(for: row.id), !isRepositoryRemoving {
        baseRow.contextMenu {
          rowContextMenu(worktree: worktree, row: row)
        }
      } else {
        baseRow.disabled(isRepositoryRemoving)
      }
    }
    .contentShape(.dragPreview, .rect)
    .contentShape(.interaction, .rect)
    .onTapGesture {
      selectWorktreeRow(row.id)
    }
    .accessibilityAddTraits(.isButton)
    .draggableWorktree(
      id: row.id,
      isEnabled: !moveDisabled,
      beginDrag: {
        draggingWorktreeIDs = [row.id]
        store.send(.worktreeOrdering(.setSidebarDragActive(true)))
      }
    )
    .environment(\.colorScheme, colorScheme)
    .preferredColorScheme(colorScheme)
    .onHover { hovering in
      if hovering {
        hoveredWorktreeID = row.id
      } else if hoveredWorktreeID == row.id {
        hoveredWorktreeID = nil
      }
    }
    .onDragSessionUpdated { session in
      let didEnd =
        if case .ended = session.phase {
          true
        } else if case .dataTransferCompleted = session.phase {
          true
        } else {
          false
        }
      handleWorktreeDragSession(
        draggedIDs: Set(session.draggedItemIDs(for: Worktree.ID.self)),
        didEnd: didEnd
      )
    }
  }

  private func handleWorktreeDragSession(
    draggedIDs: Set<Worktree.ID>,
    didEnd: Bool
  ) {
    if didEnd {
      draggingWorktreeIDs = []
      return
    }
    if draggedIDs != draggingWorktreeIDs {
      draggingWorktreeIDs = draggedIDs
    }
  }

  private func worktreeDropZone(
    destination: Int,
    rowIDs: [Worktree.ID],
    targetedDestination: Binding<Int?>,
    section: SidebarWorktreeSection
  ) -> some View {
    SidebarDropIndicator(isVisible: targetedDestination.wrappedValue == destination, horizontalPadding: 28)
      .onDrop(
        of: [.prowlSidebarWorktreeID],
        delegate: SidebarWorktreeDropDelegate(
          destination: destination,
          sectionIDs: rowIDs,
          targetedDestination: targetedDestination,
          onDrop: { offsets, destination in
            switch section {
            case .pinned:
              store.send(.worktreeOrdering(.pinnedWorktreesMoved(repositoryID: repository.id, offsets, destination)))
            case .unpinned:
              store.send(.worktreeOrdering(.unpinnedWorktreesMoved(repositoryID: repository.id, offsets, destination)))
            }
          },
          onDragEnded: endWorktreeDrag
        )
      )
  }

  private func selectWorktreeRow(_ worktreeID: Worktree.ID) {
    if commandKeyObserver.isPressed {
      var nextSelection = selectedWorktreeIDs
      if nextSelection.contains(worktreeID) {
        nextSelection.remove(worktreeID)
      } else {
        nextSelection.insert(worktreeID)
      }
      guard !nextSelection.isEmpty else {
        store.send(.selectWorktree(nil))
        return
      }
      let primarySelection =
        hotkeyRows.map(\.id).first(where: nextSelection.contains)
        ?? nextSelection.first
      store.send(.selectWorktree(primarySelection, focusTerminal: false))
      store.send(.setSidebarSelectedWorktreeIDs(nextSelection))
      return
    }

    store.send(.selectWorktree(worktreeID, focusTerminal: true))
    focusTerminalAfterSelection(worktreeID: worktreeID)
  }

  private func focusTerminalAfterSelection(worktreeID: Worktree.ID) {
    Task { @MainActor [terminalManager] in
      for _ in 0..<4 {
        await Task.yield()
        if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
          terminalState.focusSelectedTab()
          return
        }
      }
    }
  }

  private func endWorktreeDrag() {
    draggingWorktreeIDs = []
    targetedPinnedDropDestination = nil
    targetedUnpinnedDropDestination = nil
    store.send(.worktreeOrdering(.setSidebarDragActive(false)))
  }

  private struct WorktreeRowViewConfig {
    let displayName: String
    let worktreeName: String
    let isHovered: Bool
    let showsNotificationIndicator: Bool
    let notifications: [WorktreeTerminalNotification]
    let onFocusNotification: (WorktreeTerminalNotification) -> Void
    let shortcutHint: String?
    let pinAction: (() -> Void)?
    let archiveAction: (() -> Void)?
    let onDiffTap: (() -> Void)?
    let onStopRunScript: (() -> Void)?
    let moveDisabled: Bool
  }

  private func worktreeRowView(_ row: WorktreeRowModel, config: WorktreeRowViewConfig) -> some View {
    let isSelected = selectedWorktreeIDs.contains(row.id)
    let taskStatus = terminalManager.taskStatus(for: row.id)
    let isRunScriptRunning = terminalManager.isRunScriptRunning(for: row.id)
    let isSidebarDragActive = store.state.isSidebarDragActive
    return WorktreeRow(
      name: config.displayName,
      worktreeName: config.worktreeName,
      info: row.info,
      showsPullRequestInfo: !isSidebarDragActive && !draggingWorktreeIDs.contains(row.id),
      isHovered: config.isHovered,
      isPinned: row.isPinned,
      isMainWorktree: row.isMainWorktree,
      isLoading: row.isPending || row.isArchiving || row.isDeleting,
      taskStatus: taskStatus,
      isRunScriptRunning: isRunScriptRunning,
      showsNotificationIndicator: config.showsNotificationIndicator,
      notifications: config.notifications,
      onFocusNotification: config.onFocusNotification,
      shortcutHint: config.shortcutHint,
      pinAction: config.pinAction,
      isSelected: isSelected,
      archiveAction: config.archiveAction,
      onDiffTap: config.onDiffTap,
      onStopRunScript: config.onStopRunScript,
    )
    .tag(SidebarSelection.worktree(row.id))
    .id(SidebarScrollID.worktree(row.id))
    .typeSelectEquivalent("")
    .padding(.horizontal, 8)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 5)
          .fill(Color.accentColor.opacity(0.18))
          .padding(.horizontal, 6)
      }
    }
    .transition(.opacity)
    .moveDisabled(config.moveDisabled)
  }

  @ViewBuilder
  private func rowContextMenu(worktree: Worktree, row: WorktreeRowModel) -> some View {
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    let contextRows = contextActionRows(for: row)
    let isBulkSelection = contextRows.count > 1
    let archiveTargets =
      contextRows
      .filter { !$0.isMainWorktree }
      .map {
        RepositoriesFeature.ArchiveWorktreeTarget(
          worktreeID: $0.id,
          repositoryID: $0.repositoryID
        )
      }
    let deleteTargets =
      contextRows
      .filter { !$0.isMainWorktree }
      .map {
        RepositoriesFeature.DeleteWorktreeTarget(
          worktreeID: $0.id,
          repositoryID: $0.repositoryID
        )
      }
    let archiveTitle =
      isBulkSelection
      ? "Archive Selected Worktrees"
      : "Archive Worktree"
    let deleteTitle =
      isBulkSelection
      ? "Delete Selected Worktrees (\(deleteShortcut))"
      : "Delete Worktree (\(deleteShortcut))"
    if !row.isMainWorktree {
      if row.isPinned {
        Button("Unpin") {
          togglePin(for: worktree.id, isPinned: true)
        }
        .help("Unpin")
      } else {
        Button("Pin to top") {
          togglePin(for: worktree.id, isPinned: false)
        }
        .help("Pin to top")
      }
    }
    Button("Copy Path") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(worktree.workingDirectory.path, forType: .string)
    }
    Button("Reveal in Finder") {
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.workingDirectory.path)
    }
    if !row.isMainWorktree || isBulkSelection {
      Button(archiveTitle) {
        archiveWorktrees(archiveTargets)
      }
      .help(archiveTitle)
      .disabled(archiveTargets.isEmpty)
      Button(deleteTitle, role: .destructive) {
        deleteWorktrees(deleteTargets)
      }
      .help(deleteTitle)
      .disabled(deleteTargets.isEmpty)
    }
  }

  private func worktreeShortcutHint(for index: Int?) -> String? {
    guard let index else { return nil }
    return AppShortcuts.worktreeSelectionDisplay(at: index, in: resolvedKeybindings)
  }

  private func togglePin(for worktreeID: Worktree.ID, isPinned: Bool) {
    _ = withAnimation(.easeOut(duration: 0.2)) {
      if isPinned {
        store.send(.worktreeOrdering(.unpinWorktree(worktreeID)))
      } else {
        store.send(.worktreeOrdering(.pinWorktree(worktreeID)))
      }
    }
  }

  private func archiveWorktree(_ worktreeID: Worktree.ID) {
    store.send(.worktreeLifecycle(.requestArchiveWorktree(worktreeID, repository.id)))
  }

  private func contextActionRows(for row: WorktreeRowModel) -> [WorktreeRowModel] {
    guard selectedWorktreeIDs.count > 1, selectedWorktreeIDs.contains(row.id) else {
      return [row]
    }
    let rows = selectedWorktreeIDs.compactMap { store.state.selectedRow(for: $0) }
    return rows.isEmpty ? [row] : rows
  }

  private func archiveWorktrees(_ targets: [RepositoriesFeature.ArchiveWorktreeTarget]) {
    guard !targets.isEmpty else { return }
    if targets.count == 1, let target = targets.first {
      store.send(.worktreeLifecycle(.requestArchiveWorktree(target.worktreeID, target.repositoryID)))
    } else {
      store.send(.worktreeLifecycle(.requestArchiveWorktrees(targets)))
    }
  }

  private func deleteWorktrees(_ targets: [RepositoriesFeature.DeleteWorktreeTarget]) {
    guard !targets.isEmpty else { return }
    if targets.count == 1, let target = targets.first {
      store.send(.worktreeLifecycle(.requestDeleteWorktree(target.worktreeID, target.repositoryID)))
    } else {
      store.send(.worktreeLifecycle(.requestDeleteWorktrees(targets)))
    }
  }

  private func worktreeName(for row: WorktreeRowModel) -> String {
    if row.isMainWorktree {
      return "Default"
    }
    if row.isPending {
      return row.detail
    }
    if row.id.contains("/") {
      let pathName = URL(fileURLWithPath: row.id).lastPathComponent
      if !pathName.isEmpty {
        return pathName
      }
    }
    if !row.detail.isEmpty, row.detail != "." {
      let detailName = URL(fileURLWithPath: row.detail).lastPathComponent
      if !detailName.isEmpty, detailName != "." {
        return detailName
      }
    }
    return row.name
  }
}
