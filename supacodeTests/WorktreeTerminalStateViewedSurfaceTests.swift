import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct WorktreeTerminalStateViewedSurfaceTests {
  @Test func surfaceIsViewedWhenSelectedFocusedAndWindowActive() {
    let (state, surfaceId) = makeViewedState()

    #expect(state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenWindowStateIsUnknown() {
    let (state, surfaceId) = makeViewedState()
    state.lastWindowIsKey = nil
    state.lastWindowIsVisible = nil

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenWindowIsNotKey() {
    let (state, surfaceId) = makeViewedState()
    state.lastWindowIsKey = false

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenCanvasManaged() {
    // Canvas mode tears down the normal-mode window observers, so the window
    // flags freeze at their pre-canvas values; a stale `true` must not mute
    // notifications while the app is in the background.
    let (state, surfaceId) = makeViewedState()
    state.isCanvasManaged = true

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func differentSurfaceIsNotViewed() {
    let (state, _) = makeViewedState()

    #expect(!state.isViewedSurface(UUID()))
  }

  @Test func inactiveFocusedCompletionPollRemainsUnread() async {
    let fixture = makeDetectionFixture()
    fixture.state.lastWindowIsKey = false
    fixture.state.surfaceAgentStates[fixture.surface.id] = PaneAgentState(
      detectedAgent: .claude,
      state: .working,
      seen: true
    )
    fixture.state.agentDetectionPresenceBySurface[fixture.surface.id] = AgentDetectionPresence(
      currentAgent: .claude
    )
    fixture.state.lastAgentScreenScanBySurface[fixture.surface.id] = WorktreeTerminalState.AgentScreenScan(
      agent: .claude,
      text: "",
      detection: AgentScreenDetection(state: .idle, reason: .legacyDetector)
    )

    #expect(await fixture.state.detectAgentState(for: fixture.surface, tabId: fixture.tabID))
    #expect(fixture.state.surfaceAgentStates[fixture.surface.id]?.displayState == .done)
  }

  @Test func inactiveFocusBookkeepingDoesNotAcknowledgeCompletion() {
    let fixture = makeDetectionFixture()
    fixture.state.lastWindowIsKey = false
    fixture.state.surfaceAgentStates[fixture.surface.id] = PaneAgentState(
      detectedAgent: .claude,
      state: .idle,
      seen: false
    )

    fixture.state.recordActiveSurface(fixture.surface, in: fixture.tabID)

    #expect(fixture.state.surfaceAgentStates[fixture.surface.id]?.displayState == .done)
  }

  private func makeViewedState() -> (WorktreeTerminalState, UUID) {
    let state = WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/wt-1",
        name: "wt-1",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    let tabId = state.tabManager.createTab(title: "tab", icon: nil)
    state.tabManager.selectTab(tabId)
    let surfaceId = UUID()
    state.focusedSurfaceIdByTab[tabId] = surfaceId
    state.isSelected = { true }
    state.lastWindowIsKey = true
    state.lastWindowIsVisible = true
    return (state, surfaceId)
  }

  private struct DetectionFixture {
    let state: WorktreeTerminalState
    let tabID: TerminalTabID
    let surface: GhosttySurfaceView
  }

  private func makeDetectionFixture() -> DetectionFixture {
    let state = WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/wt-1",
        name: "wt-1",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    let surface = GhosttySurfaceView(
      runtime: state.runtime,
      workingDirectory: state.worktree.workingDirectory,
      fontSize: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    let tabID = state.tabManager.createTab(title: "tab", icon: nil)
    state.tabManager.selectTab(tabID)
    state.surfaces[surface.id] = surface
    state.trees[tabID] = SplitTree<GhosttySurfaceView>(view: surface)
    state.focusedSurfaceIdByTab[tabID] = surface.id
    state.isSelected = { true }
    state.lastWindowIsKey = true
    state.lastWindowIsVisible = true
    return DetectionFixture(state: state, tabID: tabID, surface: surface)
  }
}
