import Bonsplit
import CoreGraphics
import Foundation
import GhosttyKit
import Observation

@MainActor
@Observable
final class WorktreeTerminalState: BonsplitDelegate {
  let controller: BonsplitController
  private let runtime: GhosttyRuntime
  private let worktree: Worktree
  private let settingsStore = RepositorySettingsStore()
  private var trees: [TabID: SplitTree<GhosttySurfaceView>] = [:]
  private var surfaces: [UUID: GhosttySurfaceView] = [:]
  private var focusedSurfaceIdByTab: [TabID: UUID] = [:]
  private var pendingSetupScript: Bool

  init(runtime: GhosttyRuntime, worktree: Worktree, runSetupScript: Bool = false) {
    self.runtime = runtime
    self.worktree = worktree
    pendingSetupScript = runSetupScript
    let configuration = BonsplitConfiguration(
      allowSplits: false,
      allowCloseTabs: true,
      allowCloseLastPane: false,
      allowTabReordering: true,
      allowCrossPaneTabMove: false,
      autoCloseEmptyPanes: false,
      contentViewLifecycle: .keepAllAlive,
      newTabPosition: .current
    )
    controller = BonsplitController(configuration: configuration)
    controller.delegate = self
  }

  func ensureInitialTab() {
    let tabIds = controller.allTabIds
    if tabIds.isEmpty {
      _ = createTab(in: nil)
      return
    }
    if tabIds.count == 1, let tabId = tabIds.first, let tab = controller.tab(tabId),
      tab.title == "Welcome"
    {
      let title = "\(worktree.name) \(nextTabIndex())"
      controller.updateTab(tabId, title: title, icon: "terminal")
    }
  }

  @discardableResult
  func createTab(in pane: PaneID?) -> TabID? {
    let title = "\(worktree.name) \(nextTabIndex())"
    guard
      let tabId = controller.createTab(
        title: title,
        icon: "terminal",
        inPane: pane
      )
    else {
      return nil
    }
    controller.selectTab(tabId)
    let tree = splitTree(for: tabId)
    if let surface = tree.root?.leftmostLeaf() {
      focusSurface(surface, in: tabId)
    }
    return tabId
  }

  @discardableResult
  func closeFocusedTab() -> Bool {
    guard let paneId = controller.focusedPaneId,
      let tab = controller.selectedTab(inPane: paneId)
    else {
      return false
    }
    let closed = controller.closeTab(tab.id)
    if closed, let nextTab = controller.selectedTab(inPane: paneId) {
      controller.selectTab(nextTab.id)
    }
    return closed
  }

  func splitTree(for tabId: TabID, initialInput: String? = nil) -> SplitTree<GhosttySurfaceView> {
    if let existing = trees[tabId] {
      return existing
    }
    let resolvedInput = initialInput ?? setupScriptInput(shouldRun: pendingSetupScript)
    if pendingSetupScript {
      pendingSetupScript = false
    }
    let surface = createSurface(tabId: tabId, initialInput: resolvedInput)
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
      let newSurface = createSurface(tabId: tabId, initialInput: nil)
      do {
        let newTree = try tree.inserting(
          view: newSurface,
          at: targetSurface,
          direction: mapSplitDirection(direction)
        )
        trees[tabId] = newTree
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
        trees[tabId] = newTree
        return true
      } catch {
        return false
      }

    case .equalizeSplits:
      trees[tabId] = tree.equalized()
      return true

    case .toggleSplitZoom:
      guard tree.isSplit else { return false }
      let newZoomed = (tree.zoomed == targetNode) ? nil : targetNode
      trees[tabId] = tree.settingZoomed(newZoomed)
      return true
    }
  }

  func performSplitOperation(_ operation: TerminalSplitTreeView.Operation, in tabId: TabID) {
    guard var tree = trees[tabId] else { return }

    switch operation {
    case .resize(let node, let ratio):
      let resizedNode = node.resizing(to: ratio)
      do {
        tree = try tree.replacing(node: node, with: resizedNode)
        trees[tabId] = tree
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
        trees[tabId] = newTree
        focusSurface(payload, in: tabId)
      } catch {
        return
      }

    case .equalize:
      trees[tabId] = tree.equalized()
    }
  }

  private func setupScriptInput(shouldRun: Bool) -> String? {
    guard shouldRun else { return nil }
    let settings = settingsStore.load(for: worktree.repositoryRootURL)
    let script = settings.setupScript
    let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return nil
    }
    if script.hasSuffix("\n") {
      return script
    }
    return "\(script)\n"
  }

  func closeAllSurfaces() {
    for surface in surfaces.values {
      surface.closeSurface()
    }
    surfaces.removeAll()
    trees.removeAll()
    focusedSurfaceIdByTab.removeAll()
  }

  func splitTabBar(
    _ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID
  ) {
    removeTree(for: tabId)
  }

  func splitTabBar(_ controller: BonsplitController, didSelectTab tab: Tab, inPane pane: PaneID) {
    let tree = splitTree(for: tab.id)
    if let focusedId = focusedSurfaceIdByTab[tab.id], let focused = surfaces[focusedId] {
      focusSurface(focused, in: tab.id)
      return
    }
    if let surface = tree.root?.leftmostLeaf() {
      focusSurface(surface, in: tab.id)
    }
  }

  private func createSurface(tabId: TabID, initialInput: String?) -> GhosttySurfaceView {
    let view = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: worktree.workingDirectory,
      initialInput: initialInput
    )
    view.bridge.onTitleChange = { [weak self, weak view] title in
      guard let self, let view else { return }
      if self.focusedSurfaceIdByTab[tabId] == view.id {
        self.controller.updateTab(tabId, title: title, icon: "terminal")
      }
    }
    view.bridge.onSplitAction = { [weak self, weak view] action in
      guard let self, let view else { return false }
      return self.performSplitAction(action, for: view.id)
    }
    view.bridge.onNewTab = { [weak self, weak view] in
      guard let self, let view else { return false }
      return self.handleNewTabRequest(from: view)
    }
    view.bridge.onCloseTab = { [weak self, weak view] mode in
      guard let self, let view else { return false }
      return self.handleCloseTabRequest(from: view, mode: mode)
    }
    view.bridge.onCloseRequest = { [weak self, weak view] processAlive in
      guard let self, let view else { return }
      self.handleCloseRequest(for: view, processAlive: processAlive)
    }
    view.onFocusChange = { [weak self, weak view] focused in
      guard let self, let view else { return }
      guard focused else { return }
      self.focusedSurfaceIdByTab[tabId] = view.id
      self.updateTabTitle(for: tabId)
    }
    surfaces[view.id] = view
    return view
  }

  private func updateTabTitle(for tabId: TabID) {
    guard let focusedId = focusedSurfaceIdByTab[tabId],
      let surface = surfaces[focusedId]
    else { return }
    if let title = surface.bridge.state.title {
      controller.updateTab(tabId, title: title, icon: "terminal")
    }
  }

  private func focusSurface(_ surface: GhosttySurfaceView, in tabId: TabID) {
    focusedSurfaceIdByTab[tabId] = surface.id
    surface.requestFocus()
    updateTabTitle(for: tabId)
  }

  private func removeTree(for tabId: TabID) {
    guard let tree = trees.removeValue(forKey: tabId) else { return }
    for surface in tree.leaves() {
      surface.closeSurface()
      surfaces.removeValue(forKey: surface.id)
    }
    focusedSurfaceIdByTab.removeValue(forKey: tabId)
  }

  private func tabId(containing surfaceId: UUID) -> TabID? {
    for (tabId, tree) in trees where tree.find(id: surfaceId) != nil {
      return tabId
    }
    return nil
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

  private func handleCloseRequest(for view: GhosttySurfaceView, processAlive: Bool) {
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
    let newTree = tree.removing(node)
    view.closeSurface()
    surfaces.removeValue(forKey: view.id)
    if newTree.isEmpty {
      trees.removeValue(forKey: tabId)
      focusedSurfaceIdByTab.removeValue(forKey: tabId)
      controller.closeTab(tabId)
      return
    }
    trees[tabId] = newTree
    if focusedSurfaceIdByTab[tabId] == view.id {
      if let nextSurface = newTree.root?.leftmostLeaf() {
        focusSurface(nextSurface, in: tabId)
      } else {
        focusedSurfaceIdByTab.removeValue(forKey: tabId)
      }
    }
  }

  private func handleNewTabRequest(from view: GhosttySurfaceView) -> Bool {
    let paneId = controller.focusedPaneId
    return createTab(in: paneId) != nil
  }

  private func handleCloseTabRequest(
    from view: GhosttySurfaceView,
    mode: ghostty_action_close_tab_mode_e
  ) -> Bool {
    _ = view
    _ = mode
    return closeFocusedTab()
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
    for tabId in controller.allTabIds {
      guard let title = controller.tab(tabId)?.title else { continue }
      guard title.hasPrefix(prefix) else { continue }
      let suffix = title.dropFirst(prefix.count)
      guard let value = Int(suffix) else { continue }
      maxIndex = max(maxIndex, value)
    }
    return maxIndex + 1
  }
}
