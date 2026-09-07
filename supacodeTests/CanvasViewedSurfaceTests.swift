import AppKit
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct CanvasViewedSurfaceTests {
  @Test func actualCanvasFocusDoesNotDependOnNormalModeSelectionOrWindowCache() {
    let fixture = Fixture()

    #expect(fixture.state.isViewedSurface(fixture.surface.id))
    #expect(!fixture.state.isViewingWorktree())
  }

  enum UnviewedCondition: CaseIterable {
    case inactiveWindow, occludedWindow, detached, hidden, hiddenAncestor
    case logicalFocusOnly, clearedFocus, otherPane, otherTab
  }

  @Test(arguments: UnviewedCondition.allCases)
  func canvasDoesNotTreatUnviewedSurfacesAsRead(condition: UnviewedCondition) {
    let fixture = Fixture()
    // Stale normal-mode flags must never override the live Canvas window.
    fixture.state.lastWindowIsKey = true
    fixture.state.lastWindowIsVisible = true
    fixture.state.isSelected = { true }

    switch condition {
    case .inactiveWindow: fixture.window.reportsKey = false
    case .occludedWindow: fixture.window.reportsVisible = false
    case .detached: fixture.surface.removeFromSuperview()
    case .hidden: fixture.surface.isHidden = true
    case .hiddenAncestor: fixture.window.contentView?.isHidden = true
    case .logicalFocusOnly: fixture.window.makeFirstResponder(nil)
    case .clearedFocus: fixture.surface.focused = false
    case .otherPane:
      fixture.state.focusedSurfaceIdByTab[fixture.tabID] = UUID()
    case .otherTab:
      let other = fixture.state.tabManager.createTab(title: "Other", icon: nil)
      fixture.state.tabManager.selectTab(other)
    }

    #expect(!fixture.state.isViewedSurface(fixture.surface.id))
  }

  @Test func becomingTheActualResponderCompletesTheViewingTransition() {
    let fixture = Fixture()
    fixture.window.makeFirstResponder(nil)
    fixture.surface.focused = true
    #expect(!fixture.state.isViewedSurface(fixture.surface.id))

    #expect(fixture.window.makeFirstResponder(fixture.surface))
    #expect(fixture.state.isViewedSurface(fixture.surface.id))

    fixture.window.reportsKey = false
    #expect(!fixture.state.isViewedSurface(fixture.surface.id))
    fixture.window.reportsKey = true
    #expect(fixture.state.isViewedSurface(fixture.surface.id))
  }

  @Test func leavingCanvasRestoresTheNormalViewingPolicy() {
    let fixture = Fixture()
    fixture.state.isCanvasManaged = false
    #expect(!fixture.state.isViewedSurface(fixture.surface.id))

    fixture.state.isSelected = { true }
    fixture.state.lastWindowIsKey = true
    fixture.state.lastWindowIsVisible = true
    #expect(fixture.state.isViewedSurface(fixture.surface.id))
  }

  private struct Fixture {
    let state: WorktreeTerminalState
    let surface: GhosttySurfaceView
    let window: CanvasTestWindow
    let tabID: TerminalTabID

    init() {
      let runtime = GhosttyRuntime()
      state = WorktreeTerminalState(
        runtime: runtime,
        worktree: Worktree(
          id: "/tmp/repo/canvas",
          name: "canvas",
          detail: "",
          workingDirectory: URL(fileURLWithPath: "/tmp/repo/canvas"),
          repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
        ),
        skipsSurfaceCreationForTesting: true
      )
      surface = GhosttySurfaceView(
        runtime: runtime,
        workingDirectory: nil,
        context: GHOSTTY_SURFACE_CONTEXT_TAB,
        skipsSurfaceCreationForTesting: true
      )
      tabID = state.tabManager.createTab(title: "Canvas", icon: nil)
      state.tabManager.selectTab(tabID)
      state.surfaces[surface.id] = surface
      state.focusedSurfaceIdByTab[tabID] = surface.id
      state.isCanvasManaged = true
      state.isSelected = { false }
      state.lastWindowIsKey = nil
      state.lastWindowIsVisible = nil

      window = CanvasTestWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: true
      )
      window.contentView?.addSubview(surface)
      #expect(window.makeFirstResponder(surface))
      // No Ghostty C surface is created in these tests, so its focus callback is skipped.
      surface.focused = true
    }
  }
}

@MainActor
private final class CanvasTestWindow: NSWindow {
  var reportsKey = true
  var reportsVisible = true

  override var isKeyWindow: Bool { reportsKey }
  override var occlusionState: NSWindow.OcclusionState { reportsVisible ? [.visible] : [] }
}
