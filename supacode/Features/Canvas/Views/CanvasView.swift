import AppKit
import SwiftUI

struct CanvasView: View {
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  let terminalManager: WorktreeTerminalManager
  var onExitToTab: () -> Void = {}
  @State private var layoutStore = CanvasLayoutStore()

  @State private var canvasOffset: CGSize = .zero
  @State private var lastCanvasOffset: CGSize = .zero
  @State private var canvasScale: CGFloat = 1.0
  @State private var lastCanvasScale: CGFloat = 1.0
  @State private var selectionState = CanvasSelectionState()
  @State private var lastTitleBarTapDate: Date = .distantPast
  @State private var activeResize: [TerminalTabID: ActiveResize] = [:]
  @State private var hasPerformedInitialFit = false
  @State private var viewportSize: CGSize = .zero

  private let minCardWidth: CGFloat = 300
  private let minCardHeight: CGFloat = 200
  private let maxCardWidth: CGFloat = 2400
  private let maxCardHeight: CGFloat = 1600
  private let titleBarHeight: CGFloat = 28
  private let cardSpacing: CGFloat = 20

  var body: some View {
    CanvasScrollContainer(offset: $canvasOffset, lastOffset: $lastCanvasOffset) {
      GeometryReader { _ in
        let activeStates = terminalManager.activeWorktreeStates
        let allCardKeys = collectCardKeys(from: activeStates)
        let allTabIDs = collectVisibleTabIDs(from: activeStates)

        // Background layer: handles canvas pan and tap-to-clear.
        Color.clear
          .onAppear {
            ensureLayouts(for: allCardKeys)
            pruneSelection(to: Set(allTabIDs), states: activeStates)
            syncBroadcastCallbacks(states: activeStates)
          }
          .onChange(of: allCardKeys) { _, newKeys in
            if newKeys.isEmpty {
              CanvasLayoutStore.hasAutoArrangedInSession = false
            }
            ensureLayouts(for: newKeys)
            syncBroadcastCallbacks(states: activeStates)
          }
          .onChange(of: allTabIDs) { _, newTabIDs in
            pruneSelection(to: Set(newTabIDs), states: activeStates)
          }
          .contentShape(.rect)
          .accessibilityAddTraits(.isButton)
          .onTapGesture { clearSelection(states: activeStates) }
          .gesture(canvasPanGesture)

        // Cards layer: one card per open tab across all worktrees.
        // Uses .offset() (not .position()) to avoid parent size proposals
        // reaching the NSView, keeping terminal grid stable during zoom.
        ForEach(activeStates, id: \.worktreeID) { state in
          ForEach(state.tabManager.tabs) { tab in
            if state.surfaceView(for: tab.id) != nil {
              let tree = state.splitTree(for: tab.id)
              let cardKey = tab.id.rawValue.uuidString
              let baseLayout = layoutStore.cardLayouts[cardKey] ?? CanvasCardLayout(position: .zero)
              let resized = resizedFrame(for: tab.id, baseLayout: baseLayout)
              let screenCenter = screenPosition(for: resized.center)
              let cardTotalHeight = resized.size.height + titleBarHeight

              CanvasCardView(
                repositoryName: Repository.name(for: state.repositoryRootURL),
                worktreeName: tab.title,
                tree: tree,
                isFocused: selectionState.primaryTabID == tab.id,
                isSelected: selectionState.selectedTabIDs.contains(tab.id),
                hasUnseenNotification: state.hasUnseenNotification(for: tab.id),
                cardSize: resized.size,
                canvasScale: canvasScale,
                showsSelectionShield: showsSelectionShield(for: tab.id),
                onTap: {
                  let cmdHeld = NSEvent.modifierFlags.contains(.command)
                  if cmdHeld {
                    handleSelectionShieldTap(tab.id, surfaceState: state, states: activeStates)
                  } else {
                    focusSingleCard(tab.id, surfaceState: state, states: activeStates)
                  }
                },
                onSelectionTap: {
                  handleSelectionShieldTap(tab.id, surfaceState: state, states: activeStates)
                },
                onDragCommit: { translation in commitDrag(for: cardKey, translation: translation) },
                onResize: { edge, translation in
                  activeResize[tab.id] = ActiveResize(
                    edge: edge,
                    translation: CGSize(
                      width: translation.width / canvasScale,
                      height: translation.height / canvasScale
                    )
                  )
                },
                onResizeEnd: { commitResize(for: tab.id, cardKey: cardKey, surfaces: tree.leaves()) },
                onSplitOperation: { operation in
                  state.performSplitOperation(operation, in: tab.id)
                  if selectionState.isBroadcasting {
                    syncBroadcastCallbacks(states: activeStates)
                  }
                },
                onTitleBarTap: {
                  let wasAlreadyFocused =
                    selectionState.primaryTabID == tab.id
                    && selectionState.selectedTabIDs.count <= 1
                  focusSingleCard(tab.id, surfaceState: state, states: activeStates)
                  let now = Date()
                  if wasAlreadyFocused,
                    now.timeIntervalSince(lastTitleBarTapDate) <= NSEvent.doubleClickInterval
                  {
                    onExitToTab()
                  }
                  lastTitleBarTapDate = now
                }
              )
              .scaleEffect(canvasScale, anchor: .center)
              .offset(
                x: screenCenter.x - resized.size.width / 2,
                y: screenCenter.y - cardTotalHeight / 2
              )
              .zIndex(zIndex(for: tab.id))
            }
          }
        }
      }
      .contentShape(.rect)
      .simultaneousGesture(canvasZoomGesture)
      .onGeometryChange(for: CGSize.self) { proxy in
        proxy.size
      } action: { newSize in
        viewportSize = newSize
        if !hasPerformedInitialFit {
          hasPerformedInitialFit = true
          if !CanvasLayoutStore.hasAutoArrangedInSession {
            CanvasLayoutStore.hasAutoArrangedInSession = true
            arrangeCards()
          }
          fitToView(canvasSize: newSize)
        }
      }
    }
    .overlay(alignment: .bottomTrailing) {
      canvasToolbar
    }
    .onKeyPress(.escape) {
      guard selectionState.isBroadcasting else { return .ignored }
      clearSelection(states: terminalManager.activeWorktreeStates)
      return .handled
    }
    .onKeyPress(AppShortcuts.selectAllCanvasCards.keyEquivalent, phases: .down) { keyPress in
      guard keyPress.modifiers == AppShortcuts.selectAllCanvasCards.modifiers else { return .ignored }
      selectAllCards()
      return .handled
    }
    .task { activateCanvas() }
    .onDisappear { deactivateCanvas() }
  }

  private func showsSelectionShield(for tabID: TerminalTabID) -> Bool {
    if commandKeyObserver.isPressed { return true }
    if selectionState.isSelecting { return true }
    if selectionState.isBroadcasting, selectionState.primaryTabID != tabID { return true }
    return false
  }

  // MARK: - Canvas Gestures

  private var canvasPanGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        canvasOffset = CGSize(
          width: lastCanvasOffset.width + value.translation.width,
          height: lastCanvasOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastCanvasOffset = canvasOffset
      }
  }

  private var canvasZoomGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let newScale = max(0.25, min(2.0, lastCanvasScale * value.magnification))
        let anchor = value.startLocation

        // Keep the canvas point under the pinch center fixed:
        // screenPos = canvasPoint * scale + offset
        // → canvasPoint = (anchor - lastOffset) / lastScale
        // → newOffset  = anchor - canvasPoint * newScale
        let canvasX = (anchor.x - lastCanvasOffset.width) / lastCanvasScale
        let canvasY = (anchor.y - lastCanvasOffset.height) / lastCanvasScale

        canvasOffset = CGSize(
          width: anchor.x - canvasX * newScale,
          height: anchor.y - canvasY * newScale
        )
        canvasScale = newScale
      }
      .onEnded { _ in
        lastCanvasScale = canvasScale
        lastCanvasOffset = canvasOffset
      }
  }

  // MARK: - Layout

  /// Batch-position all cards that don't have stored layouts yet.
  /// Uses a single, consistent column count to avoid overlap between
  /// cards positioned in different passes.
  private func ensureLayouts(for cardKeys: [String]) {
    let unpositioned = cardKeys.filter { layoutStore.cardLayouts[$0] == nil }
    guard !unpositioned.isEmpty else { return }

    // Count only VISIBLE cards that already have layouts (ignores stale entries).
    let positionedCount = cardKeys.count - unpositioned.count
    // For incremental adds, preserve the existing grid shape.
    // For initial layout, use total count for a balanced grid.
    let columns =
      positionedCount > 0
      ? gridColumns(for: positionedCount)
      : gridColumns(for: cardKeys.count)

    // Build locally, assign once to trigger a single save.
    var layouts = layoutStore.cardLayouts
    for (offset, key) in unpositioned.enumerated() {
      layouts[key] = CanvasCardLayout(
        position: gridPosition(index: positionedCount + offset, columns: columns)
      )
    }
    layoutStore.cardLayouts = layouts
  }

  /// Balanced grid: columns ≈ sqrt(N). No viewport constraint — the canvas
  /// is infinite and fitToView handles zoom.
  private func gridColumns(for count: Int) -> Int {
    max(1, Int(ceil(sqrt(Double(count)))))
  }

  private func gridPosition(index: Int, columns: Int) -> CGPoint {
    let cardW = CanvasCardLayout.defaultSize.width
    let cardH = CanvasCardLayout.defaultSize.height + titleBarHeight
    let row = index / columns
    let col = index % columns
    return CGPoint(
      x: cardSpacing + (cardW + cardSpacing) * CGFloat(col) + cardW / 2,
      y: cardSpacing + (cardH + cardSpacing) * CGFloat(row) + cardH / 2
    )
  }

  /// Compute effective center and size accounting for resize only (not drag).
  /// Drag is applied separately via `.offset()` to avoid layout passes.
  private func resizedFrame(
    for tabID: TerminalTabID,
    baseLayout: CanvasCardLayout
  ) -> (center: CGPoint, size: CGSize) {
    var centerX = baseLayout.position.x
    var centerY = baseLayout.position.y
    var width = baseLayout.size.width
    var height = baseLayout.size.height

    if let resize = activeResize[tabID] {
      let (wSign, hSign) = resize.edge.resizeSigns
      if wSign != 0 {
        let newW = clampWidth(width + CGFloat(wSign) * resize.translation.width)
        centerX += CGFloat(wSign) * (newW - width) / 2
        width = newW
      }
      if hSign != 0 {
        let newH = clampHeight(height + CGFloat(hSign) * resize.translation.height)
        centerY += CGFloat(hSign) * (newH - height) / 2
        height = newH
      }
    }

    return (CGPoint(x: centerX, y: centerY), CGSize(width: width, height: height))
  }

  private func screenPosition(for canvasCenter: CGPoint) -> CGPoint {
    CGPoint(
      x: canvasCenter.x * canvasScale + canvasOffset.width,
      y: canvasCenter.y * canvasScale + canvasOffset.height
    )
  }

  private func clampWidth(_ width: CGFloat) -> CGFloat {
    max(minCardWidth, min(maxCardWidth, width))
  }

  private func clampHeight(_ height: CGFloat) -> CGFloat {
    max(minCardHeight, min(maxCardHeight, height))
  }

  // MARK: - Organize & Fit

  private func collectCardKeys(from states: [WorktreeTerminalState]) -> [String] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil ? tab.id.rawValue.uuidString : nil
      }
    }
  }

  private func collectVisibleTabIDs(from states: [WorktreeTerminalState]) -> [TerminalTabID] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil ? tab.id : nil
      }
    }
  }

  /// Reset all card positions to a clean grid layout (uniform sizes).
  private func organizeCards() {
    let keys = collectCardKeys(from: terminalManager.activeWorktreeStates)
    let columns = gridColumns(for: keys.count)
    var layouts = layoutStore.cardLayouts
    for (index, key) in keys.enumerated() {
      layouts[key] = CanvasCardLayout(
        position: gridPosition(index: index, columns: columns)
      )
    }
    layoutStore.cardLayouts = layouts
  }

  /// Arrange cards using MaxRects-BSSF bin packing. Preserves each card's
  /// current size and finds a compact layout whose aspect ratio matches
  /// the viewport.
  private func arrangeCards() {
    let keys = collectCardKeys(from: terminalManager.activeWorktreeStates)
    guard !keys.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

    let cards: [CanvasCardPacker.CardInfo] = keys.map { key in
      let size = layoutStore.cardLayouts[key]?.size ?? CanvasCardLayout.defaultSize
      return CanvasCardPacker.CardInfo(key: key, size: size)
    }

    let packer = CanvasCardPacker(spacing: cardSpacing, titleBarHeight: titleBarHeight)
    let targetRatio = viewportSize.width / viewportSize.height
    let result = packer.pack(cards: cards, targetRatio: targetRatio)

    guard !result.layouts.isEmpty else { return }
    layoutStore.cardLayouts = result.layouts
  }

  /// Adjust scale and offset so all cards fit within the viewport.
  private func fitToView(canvasSize: CGSize) {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return }

    let keys = collectCardKeys(from: terminalManager.activeWorktreeStates)
    guard !keys.isEmpty else { return }

    // Bounding box of all cards in canvas coordinates
    var minX = CGFloat.infinity
    var minY = CGFloat.infinity
    var maxX = -CGFloat.infinity
    var maxY = -CGFloat.infinity

    for key in keys {
      guard let layout = layoutStore.cardLayouts[key] else { continue }
      let halfW = layout.size.width / 2
      let halfH = (layout.size.height + titleBarHeight) / 2
      minX = min(minX, layout.position.x - halfW)
      minY = min(minY, layout.position.y - halfH)
      maxX = max(maxX, layout.position.x + halfW)
      maxY = max(maxY, layout.position.y + halfH)
    }

    guard minX.isFinite else { return }

    let padding: CGFloat = 40
    let bboxW = maxX - minX + padding * 2
    let bboxH = maxY - minY + padding * 2
    let bboxCenterX = (minX + maxX) / 2
    let bboxCenterY = (minY + maxY) / 2

    let newScale = max(0.25, min(1.0, min(canvasSize.width / bboxW, canvasSize.height / bboxH)))

    canvasOffset = CGSize(
      width: canvasSize.width / 2 - bboxCenterX * newScale,
      height: canvasSize.height / 2 - bboxCenterY * newScale
    )
    canvasScale = newScale
    lastCanvasScale = newScale
    lastCanvasOffset = canvasOffset
  }

  /// Remove stored layouts for tabs that no longer exist.
  private func cleanStaleLayouts() {
    let visibleKeys = Set(collectCardKeys(from: terminalManager.activeWorktreeStates))
    let staleKeys = layoutStore.cardLayouts.keys.filter { !visibleKeys.contains($0) }
    guard !staleKeys.isEmpty else { return }
    var layouts = layoutStore.cardLayouts
    for key in staleKeys {
      layouts.removeValue(forKey: key)
    }
    layoutStore.cardLayouts = layouts
  }

  private var canvasToolbar: some View {
    HStack(spacing: 8) {
      if selectionState.isBroadcasting {
        Label(
          "Broadcasting to \(selectionState.selectedTabIDs.count) cards",
          systemImage: "dot.radiowaves.left.and.right"
        )
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar, in: Capsule())
      }

      Button {
        selectAllCards()
      } label: {
        Image(systemName: "checkmark.rectangle.stack")
          .font(.body)
          .accessibilityLabel("Select All")
      }
      .buttonStyle(.bordered)
      .help("Select all cards for broadcast (\(AppShortcuts.selectAllCanvasCards.display))")

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          arrangeCards()
          fitToView(canvasSize: viewportSize)
        }
      } label: {
        Image(systemName: "rectangle.3.group")
          .font(.body)
          .accessibilityLabel("Arrange")
      }
      .buttonStyle(.bordered)
      .help("Arrange cards preserving sizes")

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          organizeCards()
          fitToView(canvasSize: viewportSize)
        }
      } label: {
        Image(systemName: "square.grid.2x2")
          .font(.body)
          .accessibilityLabel("Organize")
      }
      .buttonStyle(.bordered)
      .help("Organize cards in a uniform grid")
    }
    .padding()
  }

  private func zIndex(for tabID: TerminalTabID) -> Double {
    if selectionState.primaryTabID == tabID {
      return 2
    }
    if selectionState.selectedTabIDs.contains(tabID) {
      return 1
    }
    return 0
  }

  // MARK: - Drag

  private func commitDrag(for cardKey: String, translation: CGSize) {
    if var layout = layoutStore.cardLayouts[cardKey] {
      layout.position.x += translation.width
      layout.position.y += translation.height
      layoutStore.cardLayouts[cardKey] = layout
    }
  }

  // MARK: - Resize

  private func commitResize(for tabID: TerminalTabID, cardKey: String, surfaces: [GhosttySurfaceView]) {
    guard activeResize[tabID] != nil else { return }
    if var layout = layoutStore.cardLayouts[cardKey] {
      let resized = resizedFrame(for: tabID, baseLayout: layout)
      layout.position = resized.center
      layout.size = resized.size
      layoutStore.cardLayouts[cardKey] = layout
    }
    activeResize[tabID] = nil
    for surface in surfaces {
      surface.needsLayout = true
      surface.needsDisplay = true
    }
  }

  private func selectAllCards() {
    let activeStates = terminalManager.activeWorktreeStates
    let allTabIDs = collectVisibleTabIDs(from: activeStates)
    guard allTabIDs.count > 1 else { return }
    mutateSelection(states: activeStates) { state in
      state.selectAll(allTabIDs)
    }
  }

  // MARK: - Selection and Focus

  private func focusSingleCard(
    _ tabID: TerminalTabID,
    surfaceState _: WorktreeTerminalState,
    states: [WorktreeTerminalState]
  ) {
    mutateSelection(states: states) { state in
      state.focusSingle(tabID)
    }
  }

  private func handleSelectionShieldTap(
    _ tabID: TerminalTabID,
    surfaceState _: WorktreeTerminalState,
    states: [WorktreeTerminalState]
  ) {
    let cmdHeld = NSEvent.modifierFlags.contains(.command)
    mutateSelection(states: states) { state in
      if cmdHeld {
        state.toggleSelection(tabID)
      } else if state.isBroadcasting, state.selectedTabIDs.contains(tabID) {
        state.setPrimary(tabID)
      } else {
        state.focusSingle(tabID)
      }
    }
  }

  private func clearSelection(states: [WorktreeTerminalState]) {
    mutateSelection(states: states) { state in
      state.clear()
    }
  }

  private func pruneSelection(to visibleTabIDs: Set<TerminalTabID>, states: [WorktreeTerminalState]) {
    let previousPrimaryTabID = selectionState.primaryTabID
    selectionState.prune(to: visibleTabIDs)
    syncPrimaryFocus(from: previousPrimaryTabID, to: selectionState.primaryTabID, states: states)
    syncBroadcastCallbacks(states: states)
  }

  private func mutateSelection(
    states: [WorktreeTerminalState],
    mutation: (inout CanvasSelectionState) -> Void
  ) {
    let previousPrimaryTabID = selectionState.primaryTabID
    mutation(&selectionState)
    selectionState.prune(to: Set(collectVisibleTabIDs(from: states)))
    syncPrimaryFocus(from: previousPrimaryTabID, to: selectionState.primaryTabID, states: states)
    syncBroadcastCallbacks(states: states)
  }

  private func syncPrimaryFocus(
    from previousTabID: TerminalTabID?,
    to newTabID: TerminalTabID?,
    states: [WorktreeTerminalState]
  ) {
    if let previousTabID, previousTabID != newTabID {
      unfocusTab(previousTabID, states: states)
    }

    guard let newTabID,
      let ownerState = states.first(where: { $0.surfaceView(for: newTabID) != nil }),
      let surfaceView = ownerState.surfaceView(for: newTabID)
    else {
      terminalManager.canvasFocusedWorktreeID = nil
      return
    }

    ownerState.tabManager.selectTab(newTabID)
    terminalManager.canvasFocusedWorktreeID = ownerState.worktreeID
    surfaceView.focusDidChange(true)
    surfaceView.requestFocus()
  }

  private func unfocusTab(_ tabID: TerminalTabID, states: [WorktreeTerminalState]) {
    guard let state = states.first(where: { $0.surfaceView(for: tabID) != nil }) else { return }
    for surface in state.splitTree(for: tabID).leaves() {
      surface.focusDidChange(false)
    }
  }

  private func syncBroadcastCallbacks(states: [WorktreeTerminalState]) {
    clearBroadcastCallbacks(states: states)

    guard selectionState.isBroadcasting,
      let primaryTabID = selectionState.primaryTabID,
      let primaryState = terminalManager.stateContaining(tabId: primaryTabID)
    else {
      return
    }

    let selectedTabIDs = selectionState.selectedTabIDs
    let beginBroadcast = { selectionState.beginBroadcastInteractionIfNeeded() }
    for primarySurface in primaryState.splitTree(for: primaryTabID).leaves() {
      primarySurface.onCommittedText = { [terminalManager, selectedTabIDs, primaryTabID, beginBroadcast] text in
        Task { @MainActor in
          beginBroadcast()
          terminalManager.broadcastCommittedText(text, from: primaryTabID, to: selectedTabIDs)
        }
      }
      primarySurface.onMirroredKey = {
        [terminalManager, selectedTabIDs, primaryTabID, beginBroadcast] mirroredKey in
        Task { @MainActor in
          beginBroadcast()
          terminalManager.broadcastMirroredKey(mirroredKey, from: primaryTabID, to: selectedTabIDs)
        }
      }
    }
  }

  private func clearBroadcastCallbacks(states: [WorktreeTerminalState]) {
    for state in states {
      for tab in state.tabManager.tabs {
        for surface in state.splitTree(for: tab.id).leaves() {
          surface.onCommittedText = nil
          surface.onMirroredKey = nil
        }
      }
    }
  }

  // MARK: - Occlusion

  private func activateCanvas() {
    cleanStaleLayouts()

    let activeStates = terminalManager.activeWorktreeStates

    // Auto-focus the card that was active before entering canvas.
    if let selectedID = terminalManager.selectedWorktreeID,
      let state = activeStates.first(where: { $0.worktreeID == selectedID }),
      let tabID = state.tabManager.selectedTabId
    {
      selectionState.focusSingle(tabID)
      syncPrimaryFocus(from: nil, to: tabID, states: activeStates)
    } else {
      selectionState.clear()
      syncBroadcastCallbacks(states: activeStates)
    }

    for state in activeStates {
      state.setAllSurfacesOccluded()
    }
    // Un-occlude all surfaces visible on canvas (including split panes)
    for state in activeStates {
      for tab in state.tabManager.tabs {
        for surface in state.splitTree(for: tab.id).leaves() {
          surface.setOcclusion(true)
        }
      }
    }
  }

  private func deactivateCanvas() {
    clearBroadcastCallbacks(states: terminalManager.activeWorktreeStates)
    selectionState.clear()
    // Don't occlude surfaces here. In SwiftUI's if/else view swap,
    // onAppear fires before onDisappear, so occluding here would undo
    // WorktreeTerminalTabsView.onAppear's syncFocus() and cause blank
    // surfaces. Cleanup of non-selected worktrees is handled by
    // setSelectedWorktreeID in the async exit flow.
  }
}

private struct ActiveResize {
  let edge: CanvasCardView.CardResizeEdge
  var translation: CGSize
}

// MARK: - Scroll Container

/// Wraps SwiftUI content in an NSView whose `scrollWheel` override catches
/// unhandled scroll-wheel events and translates them into canvas-offset changes.
/// Focused terminals consume their own scroll events (they don't call super),
/// so only events over empty space or unfocused cards reach this container.
private struct CanvasScrollContainer<Content: View>: NSViewRepresentable {
  @Binding var offset: CGSize
  @Binding var lastOffset: CGSize
  @ViewBuilder var content: Content

  func makeCoordinator() -> CanvasScrollCoordinator {
    CanvasScrollCoordinator()
  }

  func makeNSView(context: Context) -> CanvasScrollContainerView {
    let container = CanvasScrollContainerView()
    let hosting = NSHostingView(rootView: content)
    hosting.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: container.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    container.scrollCoordinator = context.coordinator
    return container
  }

  func updateNSView(_ nsView: CanvasScrollContainerView, context: Context) {
    context.coordinator.offset = $offset
    context.coordinator.lastOffset = $lastOffset
    if let hosting = nsView.subviews.first as? NSHostingView<Content> {
      hosting.rootView = content
    }
  }
}

private class CanvasScrollCoordinator {
  var offset: Binding<CGSize> = .constant(.zero)
  var lastOffset: Binding<CGSize> = .constant(.zero)

  func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
    let current = offset.wrappedValue
    let newOffset = CGSize(
      width: current.width + deltaX,
      height: current.height + deltaY
    )
    offset.wrappedValue = newOffset
    lastOffset.wrappedValue = newOffset
  }
}

private class CanvasScrollContainerView: NSView {
  var scrollCoordinator: CanvasScrollCoordinator?

  override func scrollWheel(with event: NSEvent) {
    if event.phase == .began || event.phase == .changed || event.phase == .mayBegin || event.momentumPhase != [] {
      scrollCoordinator?.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
      return
    }
    super.scrollWheel(with: event)
  }
}
