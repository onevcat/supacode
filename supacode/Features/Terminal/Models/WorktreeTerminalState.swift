import AppKit
import CoreGraphics
import Foundation
import GhosttyKit
import Observation
import Sharing

private let terminalStateLogger = SupaLogger("TerminalState")

@MainActor
@Observable
final class WorktreeTerminalState {
  struct SurfaceActivity: Equatable {
    let isVisible: Bool
    let isFocused: Bool
  }

  let tabManager: TerminalTabManager
  private let runtime: GhosttyRuntime
  private let worktree: Worktree
  @ObservationIgnored
  @SharedReader private var repositorySettings: RepositorySettings
  private var trees: [TerminalTabID: SplitTree<GhosttySurfaceView>] = [:]
  private var surfaces: [UUID: GhosttySurfaceView] = [:]
  private var focusedSurfaceIdByTab: [TerminalTabID: UUID] = [:]
  var tabIsRunningById: [TerminalTabID: Bool] = [:]
  private var runScriptTabId: TerminalTabID?
  private var pendingSetupScript: Bool
  private var defaultFontSize: Float32?
  private var isEnsuringInitialTab = false
  private var lastReportedTaskStatus: WorktreeTaskStatus?
  private var lastEmittedFocusSurfaceId: UUID?
  private var lastWindowIsKey: Bool?
  private var lastWindowIsVisible: Bool?
  var notifications: [WorktreeTerminalNotification] = []
  var notificationsEnabled = true
  private var commandFinishedNotificationEnabled = true
  private var commandFinishedNotificationThreshold = 10
  private var lastKeyInputTimeBySurface: [UUID: ContinuousClock.Instant] = [:]
  var hasUnseenNotification: Bool {
    notifications.contains { !$0.isRead }
  }

  func hasUnseenNotification(for tabId: TerminalTabID) -> Bool {
    let surfaceIds = trees[tabId]?.leaves().map(\.id) ?? []
    return notifications.contains { !$0.isRead && surfaceIds.contains($0.surfaceId) }
  }
  var isSelected: () -> Bool = { false }
  var onNotificationReceived: ((String, String) -> Void)?
  var onNotificationIndicatorChanged: (() -> Void)?
  var onTabCreated: (() -> Void)?
  var onTabClosed: (() -> Void)?
  var onFocusChanged: ((UUID) -> Void)?
  var onTaskStatusChanged: ((WorktreeTaskStatus) -> Void)?
  var onRunScriptStatusChanged: ((Bool) -> Void)?
  var onCommandPaletteToggle: (() -> Void)?
  var onSetupScriptConsumed: (() -> Void)?
  var onFontSizeAdjusted: (() -> Void)?

  init(
    runtime: GhosttyRuntime,
    worktree: Worktree,
    runSetupScript: Bool = false,
    defaultFontSize: Float32? = nil
  ) {
    self.runtime = runtime
    self.worktree = worktree
    self.pendingSetupScript = runSetupScript
    self.defaultFontSize = defaultFontSize
    self.tabManager = TerminalTabManager()
    _repositorySettings = SharedReader(
      wrappedValue: RepositorySettings.default,
      .repositorySettings(worktree.repositoryRootURL)
    )
  }

  var worktreeID: Worktree.ID { worktree.id }
  var worktreeName: String { worktree.name }
  var repositoryRootURL: URL { worktree.repositoryRootURL }

  var activeSurfaceView: GhosttySurfaceView? {
    guard let selectedTabId = tabManager.selectedTabId,
      let surfaceId = focusedSurfaceIdByTab[selectedTabId]
    else {
      return nil
    }
    return surfaces[surfaceId]
  }

  func surfaceView(for tabId: TerminalTabID) -> GhosttySurfaceView? {
    guard let surfaceId = focusedSurfaceIdByTab[tabId] else { return nil }
    return surfaces[surfaceId]
  }

  @discardableResult
  func insertCommittedText(_ text: String, in tabId: TerminalTabID) -> Bool {
    guard let surface = surfaceView(for: tabId) else { return false }
    surface.insertCommittedTextForBroadcast(text)
    return true
  }

  @discardableResult
  func applyMirroredKey(_ key: MirroredTerminalKey, in tabId: TerminalTabID) -> Bool {
    guard let surface = surfaceView(for: tabId) else { return false }
    return surface.applyMirroredKeyForBroadcast(key)
  }

  var taskStatus: WorktreeTaskStatus {
    tabIsRunningById.values.contains(true) ? .running : .idle
  }

  var isRunScriptRunning: Bool {
    runScriptTabId != nil
  }

  func setDefaultFontSize(_ fontSize: Float32?) {
    defaultFontSize = fontSize
  }

  func focusedFontSize() -> Float32? {
    guard let surfaceId = currentFocusedSurfaceId() else { return nil }
    return inheritedSurfaceConfig(fromSurfaceId: surfaceId, context: GHOSTTY_SURFACE_CONTEXT_TAB).fontSize
  }

  func ensureInitialTab(focusing: Bool) {
    guard tabManager.tabs.isEmpty else { return }
    guard !isEnsuringInitialTab else { return }
    isEnsuringInitialTab = true
    Task {
      let setupScript: String?
      if pendingSetupScript {
        setupScript = repositorySettings.setupScript
      } else {
        setupScript = nil
      }
      await MainActor.run {
        if tabManager.tabs.isEmpty {
          _ = createTab(focusing: focusing, setupScript: setupScript)
        }
        isEnsuringInitialTab = false
      }
    }
  }

  @discardableResult
  func createTab(
    focusing: Bool = true,
    setupScript: String? = nil,
    initialInput: String? = nil,
    inheritingFromSurfaceId: UUID? = nil
  ) -> TerminalTabID? {
    let context: ghostty_surface_context_e =
      tabManager.tabs.isEmpty
      ? GHOSTTY_SURFACE_CONTEXT_WINDOW
      : GHOSTTY_SURFACE_CONTEXT_TAB
    let resolvedInheritanceSurfaceId = inheritingFromSurfaceId ?? currentFocusedSurfaceId()
    let title = "\(worktree.name) \(nextTabIndex())"
    let setupInput = setupScriptInput(setupScript: setupScript)
    let commandInput = initialInput.flatMap { runScriptInput($0) }
    let resolvedInput: String?
    switch (setupInput, commandInput) {
    case (nil, nil):
      resolvedInput = nil
    case (let setupInput?, nil):
      resolvedInput = setupInput
    case (nil, let commandInput?):
      resolvedInput = commandInput
    case (let setupInput?, let commandInput?):
      resolvedInput = setupInput + commandInput
    }
    let shouldConsumeSetupScript = pendingSetupScript && setupScript != nil
    if shouldConsumeSetupScript {
      pendingSetupScript = false
    }
    let tabId = createTab(
      TabCreation(
        title: title,
        icon: "terminal",
        isTitleLocked: false,
        initialInput: resolvedInput,
        focusing: focusing,
        inheritingFromSurfaceId: resolvedInheritanceSurfaceId,
        context: context
      )
    )
    if shouldConsumeSetupScript, tabId != nil {
      onSetupScriptConsumed?()
    }
    return tabId
  }

  @discardableResult
  func runScript(_ script: String) -> TerminalTabID? {
    guard let input = runScriptInput(script) else { return nil }
    if let existing = runScriptTabId {
      closeTab(existing)
    }
    let tabId = createTab(
      TabCreation(
        title: "RUN SCRIPT",
        icon: "play.fill",
        isTitleLocked: true,
        initialInput: input,
        focusing: true,
        inheritingFromSurfaceId: currentFocusedSurfaceId(),
        context: GHOSTTY_SURFACE_CONTEXT_TAB
      )
    )
    setRunScriptTabId(tabId)
    return tabId
  }

  @discardableResult
  func stopRunScript() -> Bool {
    guard let runScriptTabId else { return false }
    closeTab(runScriptTabId)
    return true
  }

  private struct TabCreation: Equatable {
    let title: String
    let icon: String?
    let isTitleLocked: Bool
    let initialInput: String?
    let focusing: Bool
    let inheritingFromSurfaceId: UUID?
    let context: ghostty_surface_context_e
  }

  private func createTab(_ creation: TabCreation) -> TerminalTabID? {
    let tabId = tabManager.createTab(
      title: creation.title,
      icon: creation.icon,
      isTitleLocked: creation.isTitleLocked
    )
    let tree = splitTree(
      for: tabId,
      inheritingFromSurfaceId: creation.inheritingFromSurfaceId,
      initialInput: creation.initialInput,
      context: creation.context
    )
    tabIsRunningById[tabId] = false
    if creation.focusing, let surface = tree.root?.leftmostLeaf() {
      focusSurface(surface, in: tabId)
    }
    onTabCreated?()
    return tabId
  }

  func selectTab(_ tabId: TerminalTabID) {
    tabManager.selectTab(tabId)
    focusSurface(in: tabId)
    emitTaskStatusIfChanged()
  }

  func focusSelectedTab() {
    guard let tabId = tabManager.selectedTabId else { return }
    focusSurface(in: tabId)
  }

  @discardableResult
  func focusAndInsertText(_ text: String) -> Bool {
    guard let tabId = tabManager.selectedTabId,
      let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else { return false }
    surface.requestFocus()
    surface.insertText(text, replacementRange: NSRange(location: 0, length: 0))
    return true
  }

  @discardableResult
  func focusAndRunCommand(_ text: String) -> Bool {
    guard let tabId = tabManager.selectedTabId,
      let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let command = text.trimmingCharacters(in: .newlines)
    surface.requestFocus()
    surface.insertText(command, replacementRange: NSRange(location: 0, length: 0))
    return surface.submitLine()
  }

  func syncFocus(windowIsKey: Bool, windowIsVisible: Bool) {
    lastWindowIsKey = windowIsKey
    lastWindowIsVisible = windowIsVisible
    applySurfaceActivity()
  }

  private func applySurfaceActivity() {
    let selectedTabId = tabManager.selectedTabId
    var surfaceToFocus: GhosttySurfaceView?
    for (tabId, tree) in trees {
      let focusedId = focusedSurfaceIdByTab[tabId]
      let isSelectedTab = (tabId == selectedTabId)
      let visibleSurfaceIDs = Set(tree.visibleLeaves().map(\.id))
      for surface in tree.leaves() {
        let activity = Self.surfaceActivity(
          isSurfaceVisibleInTree: visibleSurfaceIDs.contains(surface.id),
          isSelectedTab: isSelectedTab,
          windowIsVisible: lastWindowIsVisible == true,
          windowIsKey: lastWindowIsKey == true,
          focusedSurfaceID: focusedId,
          surfaceID: surface.id
        )
        surface.setOcclusion(activity.isVisible)
        surface.focusDidChange(activity.isFocused)
        if activity.isFocused {
          surfaceToFocus = surface
        }
      }
    }
    if let surfaceToFocus, surfaceToFocus.window?.firstResponder is GhosttySurfaceView {
      surfaceToFocus.window?.makeFirstResponder(surfaceToFocus)
    }
  }

  static func surfaceActivity(
    isSurfaceVisibleInTree: Bool = true,
    isSelectedTab: Bool,
    windowIsVisible: Bool,
    windowIsKey: Bool,
    focusedSurfaceID: UUID?,
    surfaceID: UUID
  ) -> SurfaceActivity {
    let isVisible = isSurfaceVisibleInTree && isSelectedTab && windowIsVisible
    let isFocused = isVisible && windowIsKey && focusedSurfaceID == surfaceID
    return SurfaceActivity(isVisible: isVisible, isFocused: isFocused)
  }

  @discardableResult
  func focusSurface(id: UUID) -> Bool {
    guard let tabId = tabId(containing: id),
      let surface = surfaces[id]
    else {
      return false
    }
    tabManager.selectTab(tabId)
    focusSurface(surface, in: tabId)
    return true
  }

  @discardableResult
  func closeFocusedTab() -> Bool {
    guard let tabId = tabManager.selectedTabId else { return false }
    closeTab(tabId)
    return true
  }

  @discardableResult
  func closeFocusedSurface() -> Bool {
    guard let tabId = tabManager.selectedTabId,
      let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else {
      return false
    }
    surface.performBindingAction("close_surface")
    return true
  }

  @discardableResult
  func performBindingActionOnFocusedSurface(_ action: String) -> Bool {
    guard let tabId = tabManager.selectedTabId,
      let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else {
      return false
    }
    surface.performBindingAction(action)
    return true
  }

  @discardableResult
  func navigateSearchOnFocusedSurface(_ direction: GhosttySearchDirection) -> Bool {
    guard let tabId = tabManager.selectedTabId,
      let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else {
      return false
    }
    surface.navigateSearch(direction)
    return true
  }

  func closeTab(_ tabId: TerminalTabID) {
    let wasRunScriptTab = tabId == runScriptTabId
    removeTree(for: tabId)
    tabManager.closeTab(tabId)
    if let selected = tabManager.selectedTabId {
      focusSurface(in: selected)
    } else {
      lastEmittedFocusSurfaceId = nil
    }
    emitTaskStatusIfChanged()
    if wasRunScriptTab {
      setRunScriptTabId(nil)
    }
    onTabClosed?()
  }

  func closeOtherTabs(keeping tabId: TerminalTabID) {
    let ids = tabManager.tabs.map(\.id).filter { $0 != tabId }
    for id in ids {
      closeTab(id)
    }
  }

  func closeTabsToRight(of tabId: TerminalTabID) {
    guard let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }) else { return }
    let ids = tabManager.tabs.dropFirst(index + 1).map(\.id)
    for id in ids {
      closeTab(id)
    }
  }

  func closeAllTabs() {
    let ids = tabManager.tabs.map(\.id)
    for id in ids {
      closeTab(id)
    }
  }

  func splitTree(
    for tabId: TerminalTabID,
    inheritingFromSurfaceId: UUID? = nil,
    initialInput: String? = nil,
    context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_TAB
  ) -> SplitTree<GhosttySurfaceView> {
    if let existing = trees[tabId] {
      return existing
    }
    let surface = createSurface(
      tabId: tabId,
      initialInput: initialInput,
      inheritingFromSurfaceId: inheritingFromSurfaceId,
      context: context
    )
    let tree = SplitTree(view: surface)
    trees[tabId] = tree
    focusedSurfaceIdByTab[tabId] = surface.id
    return tree
  }

  func performSplitAction(_ action: GhosttySplitAction, for surfaceId: UUID) -> Bool {
    guard let tabId = tabId(containing: surfaceId), var tree = trees[tabId] else {
      return false
    }
    guard let targetNode = tree.find(id: surfaceId) else { return false }
    guard let targetSurface = surfaces[surfaceId] else { return false }

    switch action {
    case .newSplit(let direction):
      let newSurface = createSurface(
        tabId: tabId,
        initialInput: nil,
        inheritingFromSurfaceId: surfaceId,
        context: GHOSTTY_SURFACE_CONTEXT_SPLIT
      )
      do {
        let newTree = try tree.inserting(
          view: newSurface,
          at: targetSurface,
          direction: mapSplitDirection(direction)
        )
        updateTree(newTree, for: tabId)
        focusSurface(newSurface, in: tabId)
        return true
      } catch {
        newSurface.closeSurface()
        surfaces.removeValue(forKey: newSurface.id)

        return false
      }

    case .gotoSplit(let direction):
      let focusDirection = mapFocusDirection(direction)
      guard let nextSurface = tree.focusTarget(for: focusDirection, from: targetNode) else {
        return false
      }
      if tree.zoomed != nil {
        tree = tree.settingZoomed(nil)
        trees[tabId] = tree
      }
      focusSurface(nextSurface, in: tabId)
      syncFocusIfNeeded()
      return true

    case .resizeSplit(let direction, let amount):
      let spatialDirection = mapResizeDirection(direction)
      do {
        let newTree = try tree.resizing(
          node: targetNode,
          by: amount,
          in: spatialDirection,
          with: CGRect(origin: .zero, size: tree.viewBounds())
        )
        updateTree(newTree, for: tabId)
        return true
      } catch {
        return false
      }

    case .equalizeSplits:
      updateTree(tree.equalized(), for: tabId)
      return true

    case .toggleSplitZoom:
      guard tree.isSplit else { return false }
      let newZoomed = (tree.zoomed == targetNode) ? nil : targetNode
      updateTree(tree.settingZoomed(newZoomed), for: tabId)
      focusSurface(targetSurface, in: tabId)
      return true
    }
  }

  func performSplitOperation(_ operation: TerminalSplitTreeView.Operation, in tabId: TerminalTabID) {
    guard var tree = trees[tabId] else { return }

    switch operation {
    case .resize(let node, let ratio):
      let resizedNode = node.resizing(to: ratio)
      do {
        tree = try tree.replacing(node: node, with: resizedNode)
        updateTree(tree, for: tabId)
      } catch {
        return
      }

    case .drop(let payloadId, let destinationId, let zone):
      guard let payload = surfaces[payloadId] else { return }
      guard let destination = surfaces[destinationId] else { return }
      if payload === destination { return }
      guard let sourceNode = tree.root?.node(view: payload) else { return }
      let treeWithoutSource = tree.removing(sourceNode)
      if treeWithoutSource.isEmpty { return }
      do {
        let newTree = try treeWithoutSource.inserting(
          view: payload,
          at: destination,
          direction: mapDropZone(zone)
        )
        updateTree(newTree, for: tabId)
        focusSurface(payload, in: tabId)
      } catch {
        return
      }

    case .equalize:
      updateTree(tree.equalized(), for: tabId)
    }
  }

  func setAllSurfacesOccluded() {
    for surface in surfaces.values {
      surface.setOcclusion(false)
      surface.focusDidChange(false)
    }
  }

  func closeAllSurfaces() {
    for surface in surfaces.values {
      surface.closeSurface()
    }
    surfaces.removeAll()
    trees.removeAll()
    focusedSurfaceIdByTab.removeAll()
    tabIsRunningById.removeAll()
    setRunScriptTabId(nil)
    tabManager.closeAll()
  }

  func makeLayoutSnapshotWorktree() -> TerminalLayoutSnapshotPayload.SnapshotWorktree? {
    terminalStateLogger.info(
      "[LayoutRestore] makeSnapshot: worktree=\(worktree.id) tabs=\(tabManager.tabs.count)"
    )
    guard !tabManager.tabs.isEmpty else {
      terminalStateLogger.info("[LayoutRestore] makeSnapshot: no tabs, returning nil")
      return nil
    }

    var snapshotTabs: [TerminalLayoutSnapshotPayload.SnapshotTab] = []
    snapshotTabs.reserveCapacity(tabManager.tabs.count)
    for tab in tabManager.tabs {
      guard let tree = trees[tab.id], let root = tree.root else {
        terminalStateLogger.warning(
          "[LayoutRestore] makeSnapshot: no tree/root for tab \(tab.id.rawValue.uuidString)"
        )
        return nil
      }
      guard let splitRoot = makeLayoutSnapshotNode(from: root) else {
        terminalStateLogger.warning(
          "[LayoutRestore] makeSnapshot: failed to snapshot split tree for tab \(tab.id.rawValue.uuidString)"
        )
        return nil
      }
      snapshotTabs.append(
        TerminalLayoutSnapshotPayload.SnapshotTab(
          tabID: tab.id.rawValue.uuidString,
          splitRoot: splitRoot
        )
      )
    }

    let result = TerminalLayoutSnapshotPayload.SnapshotWorktree(
      worktreeID: worktree.id,
      selectedTabID: tabManager.selectedTabId?.rawValue.uuidString,
      tabs: snapshotTabs
    )
    terminalStateLogger.info(
      "[LayoutRestore] makeSnapshot: success, \(snapshotTabs.count) tab(s) captured"
    )
    return result
  }

  func applyLayoutSnapshot(_ snapshot: TerminalLayoutSnapshotPayload.SnapshotWorktree) -> Bool {
    terminalStateLogger.info(
      "[LayoutRestore] applySnapshot: worktree=\(worktree.id)"
        + " snapshotWorktreeID=\(snapshot.worktreeID) tabs=\(snapshot.tabs.count)"
    )
    guard snapshot.worktreeID == worktree.id else {
      terminalStateLogger.warning("[LayoutRestore] applySnapshot: worktreeID mismatch")
      return false
    }

    // Validate snapshot structure before creating any surfaces.
    var validatedTabs: [(tabID: TerminalTabID, snapshotTab: TerminalLayoutSnapshotPayload.SnapshotTab)] = []
    var seenTabIDs: Set<TerminalTabID> = []
    for snapshotTab in snapshot.tabs {
      guard let tabUUID = UUID(uuidString: snapshotTab.tabID) else {
        terminalStateLogger.warning("[LayoutRestore] applySnapshot: invalid tab UUID \(snapshotTab.tabID)")
        return false
      }
      let tabID = TerminalTabID(rawValue: tabUUID)
      guard seenTabIDs.insert(tabID).inserted else {
        terminalStateLogger.warning("[LayoutRestore] applySnapshot: duplicate tab ID \(snapshotTab.tabID)")
        return false
      }
      validatedTabs.append((tabID: tabID, snapshotTab: snapshotTab))
    }

    let selectedTabID: TerminalTabID?
    if let selectedTabRaw = snapshot.selectedTabID {
      guard let selectedUUID = UUID(uuidString: selectedTabRaw) else {
        terminalStateLogger.warning("[LayoutRestore] applySnapshot: invalid selectedTab UUID \(selectedTabRaw)")
        return false
      }
      let candidate = TerminalTabID(rawValue: selectedUUID)
      guard seenTabIDs.contains(candidate) else {
        terminalStateLogger.warning("[LayoutRestore] applySnapshot: selectedTab not in restored tabs")
        return false
      }
      selectedTabID = candidate
    } else {
      selectedTabID = validatedTabs.first?.tabID
    }

    // Close existing surfaces BEFORE creating new ones so new surfaces
    // don't get destroyed by closeAllSurfaces().
    terminalStateLogger.info("[LayoutRestore] applySnapshot: closing existing surfaces before restore")
    closeAllSurfaces()

    // Now create new surfaces into the clean state.
    var restoredTabs: [TerminalTabItem] = []
    var restoredTrees: [TerminalTabID: SplitTree<GhosttySurfaceView>] = [:]
    var restoredFocusedSurfaceIDs: [TerminalTabID: UUID] = [:]

    for (index, entry) in validatedTabs.enumerated() {
      terminalStateLogger.info(
        "[LayoutRestore] applySnapshot: restoring tab[\(index)] id=\(entry.snapshotTab.tabID)"
      )
      guard
        let rootNode = restoreSplitNode(from: entry.snapshotTab.splitRoot, tabID: entry.tabID, isRoot: true)
      else {
        terminalStateLogger.warning("[LayoutRestore] applySnapshot: restoreSplitNode failed for tab[\(index)]")
        closeAllSurfaces()
        return false
      }
      let tree = SplitTree<GhosttySurfaceView>.restored(root: rootNode)
      restoredTrees[entry.tabID] = tree
      restoredFocusedSurfaceIDs[entry.tabID] = rootNode.leftmostLeaf().id
      restoredTabs.append(
        TerminalTabItem(
          id: entry.tabID,
          title: "\(worktree.name) \(index + 1)",
          icon: "terminal"
        )
      )
    }

    trees = restoredTrees
    focusedSurfaceIdByTab = restoredFocusedSurfaceIDs
    tabIsRunningById = Dictionary(uniqueKeysWithValues: restoredTabs.map { ($0.id, false) })
    tabManager.tabs = restoredTabs
    tabManager.selectedTabId = selectedTabID
    setRunScriptTabId(nil)

    // Explicitly unfocus all restored surfaces so only the focused one blinks.
    for surface in surfaces.values {
      surface.focusDidChange(false)
    }
    if let selectedTabID {
      focusSurface(in: selectedTabID)
    } else {
      lastEmittedFocusSurfaceId = nil
    }
    emitTaskStatusIfChanged()
    terminalStateLogger.info(
      "[LayoutRestore] applySnapshot: success, restored \(restoredTabs.count) tab(s)"
        + " selectedTab=\(selectedTabID?.rawValue.uuidString ?? "nil")"
    )
    return true
  }

  func setNotificationsEnabled(_ enabled: Bool) {
    notificationsEnabled = enabled
    if !enabled {
      markAllNotificationsRead()
    }
  }

  func setCommandFinishedNotification(enabled: Bool, threshold: Int) {
    commandFinishedNotificationEnabled = enabled
    commandFinishedNotificationThreshold = threshold
  }

  func clearNotificationIndicator() {
    markAllNotificationsRead()
  }

  func markAllNotificationsRead() {
    let previousHasUnseen = hasUnseenNotification
    for index in notifications.indices {
      notifications[index].isRead = true
    }
    emitNotificationIndicatorIfNeeded(previousHasUnseen: previousHasUnseen)
  }

  func markNotificationsRead(forSurfaceID surfaceID: UUID) {
    let previousHasUnseen = hasUnseenNotification
    for index in notifications.indices where notifications[index].surfaceId == surfaceID {
      notifications[index].isRead = true
    }
    emitNotificationIndicatorIfNeeded(previousHasUnseen: previousHasUnseen)
  }

  func dismissNotification(_ notificationID: WorktreeTerminalNotification.ID) {
    let previousHasUnseen = hasUnseenNotification
    notifications.removeAll { $0.id == notificationID }
    emitNotificationIndicatorIfNeeded(previousHasUnseen: previousHasUnseen)
  }

  func dismissAllNotifications() {
    let previousHasUnseen = hasUnseenNotification
    notifications.removeAll()
    emitNotificationIndicatorIfNeeded(previousHasUnseen: previousHasUnseen)
  }

  func needsSetupScript() -> Bool {
    pendingSetupScript
  }

  func enableSetupScriptIfNeeded() {
    if pendingSetupScript {
      return
    }
    if tabManager.tabs.isEmpty {
      pendingSetupScript = true
    }
  }

  private func setupScriptInput(setupScript: String?) -> String? {
    guard pendingSetupScript, let script = setupScript else { return nil }
    return formatCommandInput(script)
  }

  private func formatCommandInput(_ script: String) -> String? {
    makeCommandInput(
      script: script,
      environmentExportPrefix: worktree.scriptEnvironmentExportPrefix
    )
  }

  private func runScriptInput(_ script: String) -> String? {
    formatCommandInput(script)
  }

  // Appends a bare `exit`, which preserves the most recent command status in
  // bash, zsh, and fish while remaining portable across those shells.
  // Without this, the interactive shell stays alive after the script finishes
  // and GHOSTTY_ACTION_SHOW_CHILD_EXITED never fires for completion detection.
  private func blockingScriptInput(_ script: String) -> String? {
    makeBlockingScriptInput(
      script: script,
      environmentExportPrefix: worktree.scriptEnvironmentExportPrefix
    )
  }

  private func setRunScriptTabId(_ tabId: TerminalTabID?) {
    let wasRunning = runScriptTabId != nil
    runScriptTabId = tabId
    let isRunning = tabId != nil
    if wasRunning != isRunning {
      onRunScriptStatusChanged?(isRunning)
    }
  }

  private func createSurface(
    tabId: TerminalTabID,
    initialInput: String?,
    inheritingFromSurfaceId: UUID?,
    workingDirectoryOverride: URL? = nil,
    context: ghostty_surface_context_e
  ) -> GhosttySurfaceView {
    let inherited = inheritedSurfaceConfig(fromSurfaceId: inheritingFromSurfaceId, context: context)
    let resolvedFontSize = Self.resolvedFontSizeForNewSurface(
      defaultFontSize: defaultFontSize,
      inheritedFontSize: inherited.fontSize,
      context: context
    )
    let view = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: workingDirectoryOverride ?? inherited.workingDirectory ?? worktree.workingDirectory,
      initialInput: initialInput,
      fontSize: resolvedFontSize,
      context: context
    )
    // Sending a no-op font size action marks the Ghostty surface as
    // "font_size_adjusted", which prevents config reloads (triggered by
    // keybind changes on worktree switch) from resetting the font to the
    // config default.
    if resolvedFontSize != nil {
      view.performBindingAction("increase_font_size:0")
    }
    configureBridgeCallbacks(for: view, tabId: tabId)
    configureSurfaceCallbacks(for: view, tabId: tabId)
    surfaces[view.id] = view
    return view
  }

  private func configureBridgeCallbacks(for view: GhosttySurfaceView, tabId: TerminalTabID) {
    view.bridge.onTitleChange = { [weak self, weak view] title in
      guard let self, let view else { return }
      if self.focusedSurfaceIdByTab[tabId] == view.id {
        self.tabManager.updateTitle(tabId, title: title)
      }
    }
    view.bridge.onSplitAction = { [weak self, weak view] action in
      guard let self, let view else { return false }
      return self.performSplitAction(action, for: view.id)
    }
    view.bridge.onNewTab = { [weak self, weak view] in
      guard let self, let view else { return false }
      return self.createTab(inheritingFromSurfaceId: view.id) != nil
    }
    view.bridge.onCloseTab = { [weak self] _ in
      guard let self else { return false }
      self.closeTab(tabId)
      return true
    }
    view.bridge.onGotoTab = { [weak self] target in
      guard let self else { return false }
      return self.handleGotoTabRequest(target)
    }
    view.bridge.onCommandPaletteToggle = { [weak self] in
      guard let self else { return false }
      self.onCommandPaletteToggle?()
      return true
    }
    view.bridge.onProgressReport = { [weak self] _ in
      guard let self else { return }
      self.updateRunningState(for: tabId)
    }
    view.bridge.onDesktopNotification = { [weak self, weak view] title, body in
      guard let self, let view else { return }
      self.appendNotification(title: title, body: body, surfaceId: view.id)
    }
    view.bridge.onCommandFinished = { [weak self, weak view] exitCode, durationNs in
      guard let self, let view else { return }
      self.handleCommandFinished(exitCode: exitCode, durationNs: durationNs, surfaceId: view.id)
    }
    view.bridge.onCloseRequest = { [weak self, weak view] processAlive in
      guard let self, let view else { return }
      self.handleCloseRequest(for: view, processAlive: processAlive)
    }
    view.bridge.onPromptTitle = { [weak self] promptType in
      guard let self else { return }
      self.handlePromptTitle(promptType, tabId: tabId)
    }
  }

  private func configureSurfaceCallbacks(for view: GhosttySurfaceView, tabId: TerminalTabID) {
    view.onFocusChange = { [weak self, weak view] focused in
      guard let self, let view, focused else { return }
      self.focusedSurfaceIdByTab[tabId] = view.id
      self.markNotificationsRead(forSurfaceID: view.id)
      self.updateTabTitle(for: tabId)
      self.emitFocusChangedIfNeeded(view.id)
      self.emitTaskStatusIfChanged()
    }
    view.onKeyInput = { [weak self, weak view] in
      guard let self, let view else { return }
      self.recordKeyInput(forSurfaceID: view.id)
      self.markNotificationsRead(forSurfaceID: view.id)
    }
    view.onFontSizeShortcut = { [weak self] in
      guard let self else { return }
      self.onFontSizeAdjusted?()
    }
  }

  static func resolvedFontSizeForNewSurface(
    defaultFontSize: Float32?,
    inheritedFontSize: Float32?,
    context: ghostty_surface_context_e
  ) -> Float32? {
    if context == GHOSTTY_SURFACE_CONTEXT_SPLIT {
      return inheritedFontSize ?? defaultFontSize
    }
    return defaultFontSize
  }

  static func resolveSnapshotWorkingDirectory(
    from snapshotPath: String?,
    worktreeRoot: URL,
    fileManager: FileManager = .default
  ) -> URL? {
    guard let snapshotPath,
      let normalizedPath = PathPolicy.normalizePath(snapshotPath, relativeTo: worktreeRoot)
    else {
      return nil
    }

    let normalizedURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    guard PathPolicy.contains(normalizedURL, in: worktreeRoot) else {
      return nil
    }
    return normalizedURL
  }

  private struct InheritedSurfaceConfig: Equatable {
    let workingDirectory: URL?
    let fontSize: Float32?
  }

  private func inheritedSurfaceConfig(
    fromSurfaceId surfaceId: UUID?,
    context: ghostty_surface_context_e
  ) -> InheritedSurfaceConfig {
    guard let surfaceId,
      let view = surfaces[surfaceId],
      let sourceSurface = view.surface
    else {
      return InheritedSurfaceConfig(workingDirectory: nil, fontSize: nil)
    }

    let inherited = ghostty_surface_inherited_config(sourceSurface, context)
    let fontSize = inherited.font_size == 0 ? nil : inherited.font_size
    let workingDirectory = inherited.working_directory.flatMap { ptr -> URL? in
      let path = String(cString: ptr)
      if path.isEmpty {
        return nil
      }
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return InheritedSurfaceConfig(workingDirectory: workingDirectory, fontSize: fontSize)
  }

  private func currentFocusedSurfaceId() -> UUID? {
    guard let selectedTabId = tabManager.selectedTabId else { return nil }
    return focusedSurfaceIdByTab[selectedTabId]
  }

  private func handlePromptTitle(
    _ promptType: ghostty_action_prompt_title_e,
    tabId: TerminalTabID
  ) {
    guard let surfaceId = focusedSurfaceIdByTab[tabId],
      let window = surfaces[surfaceId]?.window
    else { return }
    switch promptType {
    case GHOSTTY_PROMPT_TITLE_SURFACE, GHOSTTY_PROMPT_TITLE_TAB:
      // Prowl is a single-window app so there is no per-surface window title to set.
      // Both surface and tab title prompts are treated as tab title changes for now.
      // Consider removing GHOSTTY_PROMPT_TITLE_SURFACE support entirely.
      promptTabTitle(for: tabId, in: window)
    default:
      break
    }
  }

  private func promptTabTitle(for tabId: TerminalTabID, in window: NSWindow) {
    guard let tabIndex = tabManager.tabs.firstIndex(where: { $0.id == tabId }) else { return }

    let alert = NSAlert()
    alert.messageText = "Change Tab Title"
    alert.informativeText = "Leave blank to restore the default."
    alert.alertStyle = .informational

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
    textField.stringValue = tabManager.tabs[tabIndex].title
    alert.accessoryView = textField

    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = textField

    alert.beginSheetModal(for: window) { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .alertFirstButtonReturn else { return }
        guard let self else { return }
        let newTitle = textField.stringValue
        if newTitle.isEmpty {
          self.tabManager.clearTitleOverride(tabId)
          self.updateTabTitle(for: tabId)
        } else {
          self.tabManager.overrideTitle(tabId, title: newTitle)
        }
      }
    }
  }

  private func updateTabTitle(for tabId: TerminalTabID) {
    guard let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId],
      let title = surface.bridge.state.title
    else { return }
    tabManager.updateTitle(tabId, title: title)
  }

  private func focusSurface(in tabId: TerminalTabID) {
    if let focusedId = focusedSurfaceIdByTab[tabId], let surface = surfaces[focusedId] {
      focusSurface(surface, in: tabId)
      return
    }
    let tree = splitTree(for: tabId)
    if let surface = tree.visibleLeaves().first {
      focusSurface(surface, in: tabId)
    }
  }

  private func focusSurface(_ surface: GhosttySurfaceView, in tabId: TerminalTabID) {
    let previousSurface = focusedSurfaceIdByTab[tabId].flatMap { surfaces[$0] }
    focusedSurfaceIdByTab[tabId] = surface.id
    markNotificationsRead(forSurfaceID: surface.id)
    updateTabTitle(for: tabId)
    guard tabId == tabManager.selectedTabId else { return }
    let fromSurface = (previousSurface === surface) ? nil : previousSurface
    GhosttySurfaceView.moveFocus(to: surface, from: fromSurface)
    emitFocusChangedIfNeeded(surface.id)
  }

  private func appendNotification(title: String, body: String, surfaceId: UUID) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !(trimmedTitle.isEmpty && trimmedBody.isEmpty) else { return }
    if notificationsEnabled {
      let previousHasUnseen = hasUnseenNotification
      let isRead = isSelected() && isFocusedSurface(surfaceId)
      notifications.insert(
        WorktreeTerminalNotification(
          surfaceId: surfaceId,
          title: trimmedTitle,
          body: trimmedBody,
          isRead: isRead
        ),
        at: 0
      )
      emitNotificationIndicatorIfNeeded(previousHasUnseen: previousHasUnseen)
    }
    onNotificationReceived?(trimmedTitle, trimmedBody)
  }

  /// How recently the user must have typed for us to consider the exit user-initiated.
  static let recentInteractionWindow: Duration = .seconds(3)

  private func makeLayoutSnapshotNode(
    from node: SplitTree<GhosttySurfaceView>.Node
  ) -> TerminalLayoutSnapshotPayload.SnapshotSplitNode? {
    switch node {
    case .leaf(let view):
      let cwdPath = inheritedSurfaceConfig(
        fromSurfaceId: view.id,
        context: GHOSTTY_SURFACE_CONTEXT_TAB
      ).workingDirectory?.path(percentEncoded: false)
      return .leaf(surfaceID: view.id.uuidString, cwdPath: cwdPath)
    case .split(let split):
      guard let left = makeLayoutSnapshotNode(from: split.left) else {
        return nil
      }
      guard let right = makeLayoutSnapshotNode(from: split.right) else {
        return nil
      }
      return .split(
        direction: snapshotSplitDirection(from: split.direction),
        ratio: split.ratio,
        children: [left, right]
      )
    }
  }

  private func restoreSplitNode(
    from snapshotNode: TerminalLayoutSnapshotPayload.SnapshotSplitNode,
    tabID: TerminalTabID,
    isRoot: Bool
  ) -> SplitTree<GhosttySurfaceView>.Node? {
    switch snapshotNode.kind {
    case .leaf:
      guard let surfaceID = snapshotNode.surfaceID,
        !surfaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return nil
      }
      let context: ghostty_surface_context_e = isRoot ? GHOSTTY_SURFACE_CONTEXT_TAB : GHOSTTY_SURFACE_CONTEXT_SPLIT
      let restoredWorkingDirectory = Self.resolveSnapshotWorkingDirectory(
        from: snapshotNode.cwdPath,
        worktreeRoot: worktree.workingDirectory
      )
      let view = createSurface(
        tabId: tabID,
        initialInput: nil,
        inheritingFromSurfaceId: nil,
        workingDirectoryOverride: restoredWorkingDirectory,
        context: context
      )
      return .leaf(view: view)
    case .split:
      guard let direction = snapshotNode.direction else {
        return nil
      }
      guard let ratio = snapshotNode.ratio, ratio > 0, ratio < 1 else {
        return nil
      }
      guard let children = snapshotNode.children, children.count == 2 else {
        return nil
      }
      guard let left = restoreSplitNode(from: children[0], tabID: tabID, isRoot: false) else {
        return nil
      }
      guard let right = restoreSplitNode(from: children[1], tabID: tabID, isRoot: false) else {
        return nil
      }
      return .split(
        .init(
          direction: splitDirection(from: direction),
          ratio: ratio,
          left: left,
          right: right
        )
      )
    }
  }

  private func snapshotSplitDirection(
    from direction: SplitTree<GhosttySurfaceView>.Direction
  ) -> TerminalLayoutSnapshotSplitDirection {
    switch direction {
    case .horizontal:
      .horizontal
    case .vertical:
      .vertical
    }
  }

  private func splitDirection(
    from direction: TerminalLayoutSnapshotSplitDirection
  ) -> SplitTree<GhosttySurfaceView>.Direction {
    switch direction {
    case .horizontal:
      .horizontal
    case .vertical:
      .vertical
    }
  }

  func recordKeyInput(forSurfaceID surfaceId: UUID) {
    lastKeyInputTimeBySurface[surfaceId] = .now
  }

  func handleCommandFinished(exitCode: Int?, durationNs: UInt64, surfaceId: UUID) {
    guard commandFinishedNotificationEnabled else { return }
    let durationSeconds = Int(durationNs / 1_000_000_000)
    guard durationSeconds >= commandFinishedNotificationThreshold else { return }
    // Skip user-initiated termination (Ctrl+C / kill signal)
    if let code = exitCode, code == 130 || code == 143 { return }
    // Skip if the user was recently typing in this surface (e.g. /exit, quit)
    if let lastInput = lastKeyInputTimeBySurface[surfaceId],
      ContinuousClock.now - lastInput < Self.recentInteractionWindow
    {
      return
    }

    let title = (exitCode == nil || exitCode == 0) ? "Command finished" : "Command failed"
    let formattedDuration = Self.formatDuration(durationSeconds)
    let body: String
    if let code = exitCode, code != 0 {
      body = "Failed (exit code \(code)) after \(formattedDuration)"
    } else {
      body = "Completed in \(formattedDuration)"
    }
    appendNotification(title: title, body: body, surfaceId: surfaceId)
  }

  static func formatDuration(_ seconds: Int) -> String {
    if seconds < 60 {
      return "\(seconds)s"
    }
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    if minutes < 60 {
      return remainingSeconds > 0 ? "\(minutes)m \(remainingSeconds)s" : "\(minutes)m"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
  }

  private func removeTree(for tabId: TerminalTabID) {
    guard let tree = trees.removeValue(forKey: tabId) else { return }
    for surface in tree.leaves() {
      surface.closeSurface()
      surfaces.removeValue(forKey: surface.id)
    }
    focusedSurfaceIdByTab.removeValue(forKey: tabId)
    tabIsRunningById.removeValue(forKey: tabId)
  }

  private func tabId(containing surfaceId: UUID) -> TerminalTabID? {
    for (tabId, tree) in trees where tree.find(id: surfaceId) != nil {
      return tabId
    }
    return nil
  }

  private func isFocusedSurface(_ surfaceId: UUID) -> Bool {
    guard let selectedTabId = tabManager.selectedTabId else {
      return false
    }
    return focusedSurfaceIdByTab[selectedTabId] == surfaceId
  }

  private func updateRunningState(for tabId: TerminalTabID) {
    guard let tree = trees[tabId] else { return }
    let isRunningNow = tree.leaves().contains { surface in
      isRunningProgressState(surface.bridge.state.progressState)
    }
    tabIsRunningById[tabId] = isRunningNow
    tabManager.updateDirty(tabId, isDirty: isRunningNow)
    emitTaskStatusIfChanged()
  }

  private func emitTaskStatusIfChanged() {
    let newStatus = taskStatus
    if newStatus != lastReportedTaskStatus {
      lastReportedTaskStatus = newStatus
      onTaskStatusChanged?(newStatus)
    }
  }

  private func emitFocusChangedIfNeeded(_ surfaceId: UUID) {
    guard surfaceId != lastEmittedFocusSurfaceId else { return }
    lastEmittedFocusSurfaceId = surfaceId
    onFocusChanged?(surfaceId)
  }

  private func emitNotificationIndicatorIfNeeded(previousHasUnseen: Bool) {
    if previousHasUnseen != hasUnseenNotification {
      onNotificationIndicatorChanged?()
    }
  }

  private func syncFocusIfNeeded() {
    guard lastWindowIsKey != nil, lastWindowIsVisible != nil else { return }
    applySurfaceActivity()
  }

  private func updateTree(_ tree: SplitTree<GhosttySurfaceView>, for tabId: TerminalTabID) {
    trees[tabId] = tree
    syncFocusIfNeeded()
  }

  private func isRunningProgressState(_ state: ghostty_action_progress_report_state_e?) -> Bool {
    switch state {
    case .some(GHOSTTY_PROGRESS_STATE_SET),
      .some(GHOSTTY_PROGRESS_STATE_INDETERMINATE),
      .some(GHOSTTY_PROGRESS_STATE_PAUSE),
      .some(GHOSTTY_PROGRESS_STATE_ERROR):
      return true
    default:
      return false
    }
  }

  private func mapSplitDirection(_ direction: GhosttySplitAction.NewDirection)
    -> SplitTree<GhosttySurfaceView>.NewDirection
  {
    switch direction {
    case .left:
      return .left
    case .right:
      return .right
    case .top:
      return .top
    case .down:
      return .down
    }
  }

  private func mapFocusDirection(_ direction: GhosttySplitAction.FocusDirection)
    -> SplitTree<GhosttySurfaceView>.FocusDirection
  {
    switch direction {
    case .previous:
      return .previous
    case .next:
      return .next
    case .left:
      return .spatial(.left)
    case .right:
      return .spatial(.right)
    case .top:
      return .spatial(.top)
    case .down:
      return .spatial(.down)
    }
  }

  private func mapResizeDirection(_ direction: GhosttySplitAction.ResizeDirection)
    -> SplitTree<GhosttySurfaceView>.SpatialDirection
  {
    switch direction {
    case .left:
      return .left
    case .right:
      return .right
    case .top:
      return .top
    case .down:
      return .down
    }
  }

  private func handleCloseRequest(for view: GhosttySurfaceView, processAlive _: Bool) {
    guard surfaces[view.id] != nil else { return }
    guard let tabId = tabId(containing: view.id), let tree = trees[tabId] else {
      view.closeSurface()
      surfaces.removeValue(forKey: view.id)
      return
    }
    guard let node = tree.find(id: view.id) else {
      view.closeSurface()
      surfaces.removeValue(forKey: view.id)
      return
    }
    let nextSurface =
      focusedSurfaceIdByTab[tabId] == view.id
      ? tree.focusTargetAfterClosing(node)
      : nil
    let newTree = tree.removing(node)
    view.closeSurface()
    surfaces.removeValue(forKey: view.id)
    if newTree.isEmpty {
      trees.removeValue(forKey: tabId)
      focusedSurfaceIdByTab.removeValue(forKey: tabId)
      tabManager.closeTab(tabId)
      if tabId == runScriptTabId {
        setRunScriptTabId(nil)
      }
      return
    }
    updateTree(newTree, for: tabId)
    updateRunningState(for: tabId)
    if focusedSurfaceIdByTab[tabId] == view.id {
      if let nextSurface {
        focusSurface(nextSurface, in: tabId)
      } else {
        focusedSurfaceIdByTab.removeValue(forKey: tabId)
      }
    }
  }

  private func handleGotoTabRequest(_ target: ghostty_action_goto_tab_e) -> Bool {
    let tabs = tabManager.tabs
    guard !tabs.isEmpty else { return false }
    let raw = Int(target.rawValue)
    let selectedIndex = tabManager.selectedTabId.flatMap { selected in
      tabs.firstIndex { $0.id == selected }
    }
    let targetIndex: Int
    if raw <= 0 {
      switch raw {
      case Int(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue):
        let current = selectedIndex ?? 0
        targetIndex = (current - 1 + tabs.count) % tabs.count
      case Int(GHOSTTY_GOTO_TAB_NEXT.rawValue):
        let current = selectedIndex ?? 0
        targetIndex = (current + 1) % tabs.count
      case Int(GHOSTTY_GOTO_TAB_LAST.rawValue):
        targetIndex = tabs.count - 1
      default:
        return false
      }
    } else {
      targetIndex = min(raw - 1, tabs.count - 1)
    }
    selectTab(tabs[targetIndex].id)
    return true
  }

  private func mapDropZone(_ zone: TerminalSplitTreeView.DropZone)
    -> SplitTree<GhosttySurfaceView>.NewDirection
  {
    switch zone {
    case .top:
      return .top
    case .bottom:
      return .down
    case .left:
      return .left
    case .right:
      return .right
    }
  }

  private func nextTabIndex() -> Int {
    let prefix = "\(worktree.name) "
    var maxIndex = 0
    for tab in tabManager.tabs {
      guard tab.title.hasPrefix(prefix) else { continue }
      let suffix = tab.title.dropFirst(prefix.count)
      guard let value = Int(suffix) else { continue }
      maxIndex = max(maxIndex, value)
    }
    return maxIndex + 1
  }
}

nonisolated func makeCommandInput(
  script: String,
  environmentExportPrefix: String
) -> String? {
  let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  return environmentExportPrefix + trimmed + "\n"
}

nonisolated func makeBlockingScriptInput(
  script: String,
  environmentExportPrefix: String
) -> String? {
  guard let input = makeCommandInput(
    script: script,
    environmentExportPrefix: environmentExportPrefix
  ) else {
    return nil
  }
  return input + "exit\n"
}
