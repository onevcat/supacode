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
  @State private var contextMenuHighlightedWorktreeID: Worktree.ID?
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
    .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
      contextMenuHighlightedWorktreeID = nil
    }
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
    let isWorktreeDragActive = !draggingWorktreeIDs.isEmpty
    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
      rowView(
        row,
        isRepositoryRemoving: isRepositoryRemoving,
        moveDisabled: isRepositoryRemoving || row.isDeleting || row.isArchiving,
        shortcutHint: worktreeShortcutHint(for: shortcutIndexByID[row.id])
      )
      .worktreeDropTarget(
        index: index,
        rowIDs: rowIDs,
        isEnabled: isWorktreeDragActive,
        targetedDestination: targetedDestination,
        actions: SidebarDropTargetActions(
          draggedItemID: draggingWorktreeIDs.first,
          onDrop: { offsets, destination in
            moveWorktrees(section: section, offsets: offsets, destination: destination)
          },
          onDragEnded: endWorktreeDrag
        )
      )
    }
  }

  @ViewBuilder
  private func rowView(
    _ row: WorktreeRowModel,
    isRepositoryRemoving: Bool,
    moveDisabled: Bool,
    shortcutHint: String?
  ) -> some View {
    let isWorktreeDragActive = !draggingWorktreeIDs.isEmpty
    let config = rowConfig(
      for: row,
      isRepositoryRemoving: isRepositoryRemoving,
      isWorktreeDragActive: isWorktreeDragActive,
      moveDisabled: moveDisabled,
      shortcutHint: shortcutHint
    )
    let baseRow = worktreeRowView(row, config: config)
      .disabled(isRepositoryRemoving)
      .contentShape(.dragPreview, .rect)
      .contentShape(.interaction, .rect)
      .contentShape(Rectangle())
    Group {
      if row.isRemovable, let worktree = store.state.worktree(for: row.id), !isRepositoryRemoving {
        baseRow
          .overlay {
            ContextMenuActivationOverlay {
              scheduleContextMenuHighlight(for: row.id)
            }
          }
          .contextMenu {
            rowContextMenu(worktree: worktree, row: row)
          }
      } else {
        baseRow
      }
    }
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

  private func rowConfig(
    for row: WorktreeRowModel,
    isRepositoryRemoving: Bool,
    isWorktreeDragActive: Bool,
    moveDisabled: Bool,
    shortcutHint: String?
  ) -> WorktreeRowViewConfig {
    let displayName =
      if row.isDeleting {
        "\(row.name) (deleting...)"
      } else if row.isArchiving {
        "\(row.name) (archiving...)"
      } else {
        row.name
      }
    let showsNotificationIndicator = terminalManager.hasUnseenNotifications(for: row.id)
    let notifications = terminalManager.stateIfExists(for: row.id)?.notifications ?? []
    let canShowRowActions = row.isRemovable && !isRepositoryRemoving && !isWorktreeDragActive
    return WorktreeRowViewConfig(
      displayName: displayName,
      worktreeName: worktreeName(for: row),
      isHovered: !isWorktreeDragActive && hoveredWorktreeID == row.id,
      showsNotificationIndicator: !isWorktreeDragActive && showsNotificationIndicator,
      notifications: isWorktreeDragActive ? [] : notifications,
      onFocusNotification: focusNotificationHandler(for: row.id),
      shortcutHint: shortcutHint,
      pinAction: canShowRowActions && !row.isMainWorktree ? { togglePin(for: row.id, isPinned: row.isPinned) } : nil,
      archiveAction: canShowRowActions && !row.isMainWorktree ? { archiveWorktree(row.id) } : nil,
      onDiffTap: diffTapHandler(for: row.id),
      onStopRunScript: stopRunScriptHandler(for: row.id),
      moveDisabled: moveDisabled,
    )
  }

  private func focusNotificationHandler(for worktreeID: Worktree.ID) -> (WorktreeTerminalNotification) -> Void {
    { notification in
      guard let terminalState = terminalManager.stateIfExists(for: worktreeID) else {
        return
      }
      _ = terminalState.focusSurface(id: notification.surfaceId)
    }
  }

  private func diffTapHandler(for worktreeID: Worktree.ID) -> (() -> Void)? {
    {
      guard let worktree = store.state.worktree(for: worktreeID) else { return }
      DiffWindowManager.shared.show(
        worktreeURL: worktree.workingDirectory,
        branchName: worktree.name,
        resolvedKeybindings: resolvedKeybindings
      )
    }
  }

  private func stopRunScriptHandler(for worktreeID: Worktree.ID) -> (() -> Void)? {
    terminalManager.isRunScriptRunning(for: worktreeID)
      ? { _ = terminalManager.stateIfExists(for: worktreeID)?.stopRunScript() }
      : nil
  }

  private func handleWorktreeDragSession(
    draggedIDs: Set<Worktree.ID>,
    didEnd: Bool
  ) {
    if didEnd {
      endWorktreeDrag()
      return
    }
    if !draggedIDs.isEmpty, draggedIDs != draggingWorktreeIDs {
      draggingWorktreeIDs = draggedIDs
    }
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

  private func moveWorktrees(
    section: SidebarWorktreeSection,
    offsets: IndexSet,
    destination: Int
  ) {
    switch section {
    case .pinned:
      store.send(.worktreeOrdering(.pinnedWorktreesMoved(repositoryID: repository.id, offsets, destination)))
    case .unpinned:
      store.send(.worktreeOrdering(.unpinnedWorktreesMoved(repositoryID: repository.id, offsets, destination)))
    }
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
    let showsContextMenuHighlight = contextMenuHighlightedWorktreeID == row.id && !isSelected
    let taskStatus = terminalManager.taskStatus(for: row.id)
    let isRunScriptRunning = terminalManager.isRunScriptRunning(for: row.id)
    let isWorktreeDragActive = !draggingWorktreeIDs.isEmpty
    return WorktreeRow(
      name: config.displayName,
      worktreeName: config.worktreeName,
      info: row.info,
      showsPullRequestInfo: !isWorktreeDragActive,
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
    .padding(.leading, 14)
    .padding(.trailing, 8)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 5)
          .fill(Color.accentColor.opacity(0.18))
          .padding(.horizontal, 6)
      }
    }
    .overlay {
      if showsContextMenuHighlight {
        RoundedRectangle(cornerRadius: 5)
          .stroke(Color.accentColor, lineWidth: 2)
          .padding(.horizontal, 6)
      }
    }
    .transition(.opacity)
    .moveDisabled(config.moveDisabled)
  }

  private func scheduleContextMenuHighlight(for worktreeID: Worktree.ID) {
    guard !selectedWorktreeIDs.contains(worktreeID) else { return }
    Task { @MainActor in
      contextMenuHighlightedWorktreeID = worktreeID
    }
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

private struct ContextMenuActivationOverlay: NSViewRepresentable {
  let activate: () -> Void

  func makeNSView(context: Context) -> RightClickForwardingView {
    let view = RightClickForwardingView()
    view.activate = activate
    return view
  }

  func updateNSView(_ nsView: RightClickForwardingView, context: Context) {
    nsView.activate = activate
  }

  final class RightClickForwardingView: NSView {
    var activate: (() -> Void)?
    private var isForwardingRightClick = false

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard !isForwardingRightClick,
        NSApp.currentEvent?.type == .rightMouseDown
      else {
        return nil
      }
      return bounds.contains(point) ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
      activate?()
      guard let window else { return }
      isForwardingRightClick = true
      window.sendEvent(event)
      isForwardingRightClick = false
    }
  }
}
