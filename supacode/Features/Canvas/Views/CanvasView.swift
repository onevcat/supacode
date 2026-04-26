import AppKit
import Sharing
import SwiftUI

struct CanvasView: View {
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  let terminalManager: WorktreeTerminalManager
  var onExitToTab: () -> Void = {}
  @State private var layoutStore = CanvasLayoutStore()
  @Shared(.repositoryAppearances) private var repositoryAppearances

  @State private var canvasOffset: CGSize = .zero
  @State private var lastCanvasOffset: CGSize = .zero
  @State private var canvasScale: CGFloat = 1.0
  @State private var lastCanvasScale: CGFloat = 1.0
  @State private var selectionState = CanvasSelectionState()
  @State private var lastTitleBarTapDate: Date = .distantPast
  @State private var activeResize: [TerminalTabID: ActiveResize] = [:]
  @State private var hasPerformedInitialFit = false
  @State private var viewportSize: CGSize = .zero
  @State private var showsCanvasHelp = false

  private let minCardWidth: CGFloat = 300
  private let minCardHeight: CGFloat = 200
  private let maxCardWidth: CGFloat = 2400
  private let maxCardHeight: CGFloat = 1600
  private let titleBarHeight: CGFloat = 28
  private let cardSpacing: CGFloat = 20
  /// Reserved height at the bottom of the viewport for the help button and
  /// layout toolbar so cards don't sit underneath them after auto-fit.
  /// Cards end up shifted upward by half of this amount.
  private let bottomToolbarReserve: CGFloat = 50

  var body: some View {
    let selectAllCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.selectAllCanvasCards,
      in: resolvedKeybindings
    )
    CanvasScrollContainer(
      offset: $canvasOffset,
      lastOffset: $lastCanvasOffset,
      scale: $canvasScale,
      lastScale: $lastCanvasScale
    ) {
      GeometryReader { _ in
        let activeStates = terminalManager.activeWorktreeStates
        let allCardKeys = collectCardKeys(from: activeStates)
        let allTabIDs = collectVisibleTabIDs(from: activeStates)

        // Background layer: handles canvas pan and tap-to-clear.
        Color.clear
          .onAppear {
            ensureLayouts(for: allCardKeys)
            pruneSelection(previousOrder: [], currentOrder: allTabIDs, states: activeStates)
            syncBroadcastCallbacks(states: activeStates)
          }
          .onChange(of: allCardKeys) { _, newKeys in
            if newKeys.isEmpty {
              CanvasLayoutStore.hasAutoArrangedInSession = false
            }
            ensureLayouts(for: newKeys)
            syncBroadcastCallbacks(states: activeStates)
          }
          .onChange(of: allTabIDs) { oldTabIDs, newTabIDs in
            pruneSelection(previousOrder: oldTabIDs, currentOrder: newTabIDs, states: activeStates)
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

              let repositoryAppearance = appearance(for: state.repositoryRootURL)
              CanvasCardView(
                repositoryName: Repository.name(for: state.repositoryRootURL),
                worktreeName: tab.title,
                repositoryIcon: repositoryAppearance.icon,
                repositoryColor: repositoryAppearance.color?.color,
                repositoryRootURL: state.repositoryRootURL,
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
                },
                onExpand: {
                  focusSingleCard(tab.id, surfaceState: state, states: activeStates)
                  onExitToTab()
                },
                onClose: {
                  state.closeTab(tab.id)
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
    .overlay(alignment: .bottomLeading) {
      canvasHelpButton
    }
    .onKeyPress(.escape) {
      guard selectionState.isBroadcasting else { return .ignored }
      clearSelection(states: terminalManager.activeWorktreeStates)
      return .handled
    }
    .onKeyPress(
      selectAllCanvasShortcut?.keyEquivalent ?? AppShortcuts.selectAllCanvasCards.keyEquivalent,
      phases: .down
    ) { keyPress in
      let shortcutModifiers = selectAllCanvasShortcut?.modifiers ?? AppShortcuts.selectAllCanvasCards.modifiers
      guard keyPress.modifiers == shortcutModifiers else { return .ignored }
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

    let padding: CGFloat = 30
    let bboxW = maxX - minX + padding * 2
    let bboxH = maxY - minY + padding * 2
    let bboxCenterX = (minX + maxX) / 2
    let bboxCenterY = (minY + maxY) / 2

    let newScale = max(0.25, min(1.0, min(canvasSize.width / bboxW, canvasSize.height / bboxH)))

    canvasOffset = CGSize(
      width: canvasSize.width / 2 - bboxCenterX * newScale,
      height: (canvasSize.height - bottomToolbarReserve) / 2 - bboxCenterY * newScale
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

  private var canvasHelpButton: some View {
    Button {
      showsCanvasHelp.toggle()
    } label: {
      Image(systemName: "questionmark.circle")
        .font(.body)
        .accessibilityLabel("Canvas navigation help")
    }
    .buttonStyle(.bordered)
    .help("Canvas navigation help")
    .popover(isPresented: $showsCanvasHelp, arrowEdge: .bottom) {
      canvasHelpContent
    }
    .padding()
  }

  private var canvasHelpContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Canvas Navigation")
        .font(.headline)

      VStack(alignment: .leading, spacing: 12) {
        canvasHelpRow(
          icon: "plus.magnifyingglass",
          title: "Zoom in/out",
          detail: "⌘ + scroll, or pinch gesture"
        )
        canvasHelpRow(
          icon: "hand.draw",
          title: "Pan canvas",
          detail: "Drag empty area, middle-click drag, or two-finger swipe"
        )
      }
    }
    .padding()
    .frame(width: 320, alignment: .leading)
  }

  private func canvasHelpRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(.secondary)
        .frame(width: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.callout).fontWeight(.medium)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
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
      .help(
        AppShortcuts.helpText(
          title: "Select all cards for broadcast",
          commandID: AppShortcuts.CommandID.selectAllCanvasCards,
          in: resolvedKeybindings
        ))

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

  private func pruneSelection(
    previousOrder: [TerminalTabID],
    currentOrder: [TerminalTabID],
    states: [WorktreeTerminalState]
  ) {
    let previousPrimaryTabID = selectionState.primaryTabID
    selectionState.pruneAutoAdvancingPrimary(previousOrder: previousOrder, currentOrder: currentOrder)
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

    // Mark all states as canvas-managed so that tree updates (e.g. split
    // creation) don't trigger applySurfaceActivity with stale normal-mode
    // window visibility, which would occlude every surface.
    for state in activeStates {
      state.isCanvasManaged = true
    }

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
    let activeStates = terminalManager.activeWorktreeStates
    for state in activeStates {
      state.isCanvasManaged = false
    }
    clearBroadcastCallbacks(states: activeStates)
    selectionState.clear()
    // Don't occlude surfaces here. In SwiftUI's if/else view swap,
    // onAppear fires before onDisappear, so occluding here would undo
    // WorktreeTerminalTabsView.onAppear's syncFocus() and cause blank
    // surfaces. Cleanup of non-selected worktrees is handled by
    // setSelectedWorktreeID in the async exit flow.
  }

  /// Looks up the user-pinned `RepositoryAppearance` for a given repo
  /// root URL by deriving the canonical `Repository.ID` (the
  /// path-policy-normalized path string) and querying the @Shared
  /// dict. Returns `.empty` when no entry exists, which keeps cards
  /// visually identical to before the appearance feature shipped.
  private func appearance(for repositoryRootURL: URL) -> RepositoryAppearance {
    let id =
      PathPolicy.normalizePath(
        repositoryRootURL.path(percentEncoded: false), resolvingSymlinks: true
      ) ?? repositoryRootURL.path(percentEncoded: false)
    return repositoryAppearances[id] ?? .empty
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
  @Binding var scale: CGFloat
  @Binding var lastScale: CGFloat
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
    context.coordinator.scale = $scale
    context.coordinator.lastScale = $lastScale
    if let hosting = nsView.subviews.first as? NSHostingView<Content> {
      hosting.rootView = content
    }
  }
}

private class CanvasScrollCoordinator {
  var offset: Binding<CGSize> = .constant(.zero)
  var lastOffset: Binding<CGSize> = .constant(.zero)
  var scale: Binding<CGFloat> = .constant(1.0)
  var lastScale: Binding<CGFloat> = .constant(1.0)

  func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
    let current = offset.wrappedValue
    let newOffset = CGSize(
      width: current.width + deltaX,
      height: current.height + deltaY
    )
    offset.wrappedValue = newOffset
    lastOffset.wrappedValue = newOffset
  }

  func handleZoom(deltaY: CGFloat, anchor: CGPoint, isPrecise: Bool) {
    let result = CanvasZoomMath.zoom(
      currentScale: scale.wrappedValue,
      currentOffset: offset.wrappedValue,
      deltaY: deltaY,
      anchor: anchor,
      isPrecise: isPrecise
    )
    scale.wrappedValue = result.scale
    lastScale.wrappedValue = result.scale
    offset.wrappedValue = result.offset
    lastOffset.wrappedValue = result.offset
  }

  func setOffset(_ newOffset: CGSize) {
    offset.wrappedValue = newOffset
    lastOffset.wrappedValue = newOffset
  }
}

/// Pure zoom math, extracted for testability.
enum CanvasZoomMath {
  static let minScale: CGFloat = 0.25
  static let maxScale: CGFloat = 2.0

  struct Result: Equatable {
    let scale: CGFloat
    let offset: CGSize
  }

  /// Compute the new scale and offset for a Cmd+wheel zoom step.
  /// Keeps the canvas point under `anchor` fixed under the cursor:
  /// `screen = canvas * scale + offset` ⇒ `canvas = (anchor - offset) / scale`.
  static func zoom(
    currentScale: CGFloat,
    currentOffset: CGSize,
    deltaY: CGFloat,
    anchor: CGPoint,
    isPrecise: Bool
  ) -> Result {
    let sensitivity: CGFloat = isPrecise ? 0.0025 : 0.005
    let factor = exp(deltaY * sensitivity)
    let newScale = max(minScale, min(maxScale, currentScale * factor))
    guard newScale != currentScale else {
      return Result(scale: currentScale, offset: currentOffset)
    }
    let canvasX = (anchor.x - currentOffset.width) / currentScale
    let canvasY = (anchor.y - currentOffset.height) / currentScale
    let newOffset = CGSize(
      width: anchor.x - canvasX * newScale,
      height: anchor.y - canvasY * newScale
    )
    return Result(scale: newScale, offset: newOffset)
  }
}

private class CanvasScrollContainerView: NSView {
  var scrollCoordinator: CanvasScrollCoordinator?

  /// Whether the container is actively redirecting scroll events to canvas
  /// panning (as opposed to the brief bounce period after a gesture ends).
  private var isPanning = false
  private var scrollMonitor: Any?
  /// Brief delay after finger-up to wait for momentum events.
  private var momentumTimer: Timer?
  /// Grace period after a pan gesture ends. A follow-up gesture that begins
  /// during this window is still treated as canvas panning, even if the
  /// cursor now sits on a focused terminal.
  private var bounceTimer: Timer?

  // MARK: - Middle-click pan
  private var middleButtonMonitor: Any?
  private var isMiddlePanning = false
  private var middlePanStartLocation: NSPoint = .zero
  private var middlePanStartOffset: CGSize = .zero
  private var hasPushedPanCursor = false

  override func scrollWheel(with event: NSEvent) {
    if handleZoomEventIfNeeded(event) { return }
    if event.phase == .began {
      startPanning()
    }
    if event.phase == .began || event.phase == .changed || event.phase == .mayBegin || event.momentumPhase != [] {
      scrollCoordinator?.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
      return
    }
    super.scrollWheel(with: event)
  }

  /// If the event is a Cmd+scroll, route it to canvas zoom and report `true`.
  /// Used by both the direct `scrollWheel` override and the local monitor so
  /// pressing Cmd mid-gesture switches behavior immediately.
  fileprivate func handleZoomEventIfNeeded(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command), event.scrollingDeltaY != 0 else { return false }
    let viewLocation = convert(event.locationInWindow, from: nil)
    let anchor = CGPoint(x: viewLocation.x, y: bounds.height - viewLocation.y)
    scrollCoordinator?.handleZoom(
      deltaY: event.scrollingDeltaY,
      anchor: anchor,
      isPrecise: event.hasPreciseScrollingDeltas
    )
    return true
  }

  // MARK: - Pan lifecycle

  private func startPanning() {
    isPanning = true
    momentumTimer?.invalidate()
    momentumTimer = nil
    bounceTimer?.invalidate()
    bounceTimer = nil
    guard scrollMonitor == nil else { return }
    installMonitor()
  }

  private func installMonitor() {
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, event.window === self.window else { return event }

      // Cmd toggled mid-gesture — switch to zoom for this event.
      if self.handleZoomEventIfNeeded(event) { return nil }

      // --- New gesture ------------------------------------------------
      if event.phase == .began {
        if self.isPanning {
          // Already panning (edge case). Let normal dispatch decide.
          return event
        }
        // Within the bounce window — treat as a continuation of panning.
        self.startPanning()
        self.scrollCoordinator?.handleScroll(
          deltaX: event.scrollingDeltaX,
          deltaY: event.scrollingDeltaY
        )
        return nil
      }

      // Only intercept while actively panning (not during bounce).
      guard self.isPanning else { return event }

      // --- Ongoing gesture / momentum --------------------------------
      self.momentumTimer?.invalidate()
      self.momentumTimer = nil

      if event.phase == .changed || event.momentumPhase != [] {
        self.scrollCoordinator?.handleScroll(
          deltaX: event.scrollingDeltaX,
          deltaY: event.scrollingDeltaY
        )
      }

      // Finger lifted — momentum may follow shortly.
      if event.phase == .ended || event.phase == .cancelled {
        self.momentumTimer = Timer.scheduledTimer(
          withTimeInterval: 0.1, repeats: false
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.enterBounce() }
        }
      }

      // Momentum finished.
      if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
        self.enterBounce()
      }

      return nil
    }
  }

  /// Transition from active panning to the bounce (grace) period.
  /// The monitor stays alive so a quick follow-up gesture resumes panning.
  private func enterBounce() {
    isPanning = false
    momentumTimer?.invalidate()
    momentumTimer = nil
    bounceTimer?.invalidate()
    bounceTimer = Timer.scheduledTimer(
      withTimeInterval: 0.3, repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.tearDownMonitor() }
    }
  }

  private func tearDownMonitor() {
    isPanning = false
    momentumTimer?.invalidate()
    momentumTimer = nil
    bounceTimer?.invalidate()
    bounceTimer = nil
    if let monitor = scrollMonitor {
      scrollMonitor = nil
      DispatchQueue.main.async { MainActor.assumeIsolated { NSEvent.removeMonitor(monitor) } }
    }
  }

  // MARK: - Middle-click pan

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      installMiddleButtonMonitor()
    } else {
      tearDownMiddleButtonMonitor()
    }
  }

  private func installMiddleButtonMonitor() {
    guard middleButtonMonitor == nil else { return }
    let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
    middleButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      guard let self, event.window === self.window, event.buttonNumber == 2 else { return event }

      switch event.type {
      case .otherMouseDown:
        let location = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(location) else { return event }
        self.beginMiddlePan(at: event.locationInWindow)
        return nil
      case .otherMouseDragged:
        guard self.isMiddlePanning else { return event }
        self.updateMiddlePan(to: event.locationInWindow)
        return nil
      case .otherMouseUp:
        guard self.isMiddlePanning else { return event }
        self.endMiddlePan()
        return nil
      default:
        return event
      }
    }
  }

  private func beginMiddlePan(at windowLocation: NSPoint) {
    isMiddlePanning = true
    middlePanStartLocation = windowLocation
    middlePanStartOffset = scrollCoordinator?.offset.wrappedValue ?? .zero
    if !hasPushedPanCursor {
      NSCursor.closedHand.push()
      hasPushedPanCursor = true
    }
  }

  private func updateMiddlePan(to windowLocation: NSPoint) {
    let deltaX = windowLocation.x - middlePanStartLocation.x
    // Window Y grows upward; canvas offset Y grows downward (SwiftUI top-left).
    let deltaY = middlePanStartLocation.y - windowLocation.y
    let newOffset = CGSize(
      width: middlePanStartOffset.width + deltaX,
      height: middlePanStartOffset.height + deltaY
    )
    scrollCoordinator?.setOffset(newOffset)
  }

  private func endMiddlePan() {
    isMiddlePanning = false
    if hasPushedPanCursor {
      NSCursor.pop()
      hasPushedPanCursor = false
    }
  }

  private func tearDownMiddleButtonMonitor() {
    if isMiddlePanning { endMiddlePan() }
    if let monitor = middleButtonMonitor {
      middleButtonMonitor = nil
      DispatchQueue.main.async { MainActor.assumeIsolated { NSEvent.removeMonitor(monitor) } }
    }
  }

  override func removeFromSuperview() {
    tearDownMonitor()
    tearDownMiddleButtonMonitor()
    super.removeFromSuperview()
  }
}
