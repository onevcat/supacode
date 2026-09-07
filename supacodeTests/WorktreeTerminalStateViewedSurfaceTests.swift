import Foundation
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

  enum ViewingCondition: CaseIterable {
    case viewed, inactive, hidden, unknown, canvas, otherWorktree, otherPane, otherTab
  }

  @Test(arguments: ViewingCondition.allCases, [AgentRawState.working, .blocked])
  func completionReadStateRequiresViewedSurface(condition: ViewingCondition, previousState: AgentRawState) {
    let (state, surfaceID) = makeViewedState()
    apply(condition, to: state)
    let previous = PaneAgentState(state: previousState, seen: true)

    #expect(
      state.resolvedSeen(previous: previous, stabilized: .idle, surfaceID: surfaceID) == (condition == .viewed))
  }

  @Test(arguments: ViewingCondition.allCases)
  func pollingAndAutomaticFocusOnlyReadViewedCompletions(condition: ViewingCondition) {
    let (state, surfaceID) = makeViewedState()
    apply(condition, to: state)
    let done = PaneAgentState(state: .idle, seen: false)
    state.surfaceAgentStates[surfaceID] = done

    #expect(state.resolvedSeen(previous: done, stabilized: .idle, surfaceID: surfaceID) == (condition == .viewed))
    state.markAgentSeen(surfaceID: surfaceID)
    #expect(state.surfaceAgentStates[surfaceID]?.displayState == (condition == .viewed ? .idle : .done))
  }

  @Test func returningToViewedSurfaceAcknowledgesCompletion() {
    let (state, surfaceID) = makeViewedState()
    state.lastWindowIsKey = false
    state.surfaceAgentStates[surfaceID] = PaneAgentState(state: .idle, seen: false)
    state.markAgentSeen(surfaceID: surfaceID)
    #expect(state.surfaceAgentStates[surfaceID]?.displayState == .done)

    state.lastWindowIsKey = true
    state.markAgentSeen(surfaceID: surfaceID)
    #expect(state.surfaceAgentStates[surfaceID]?.displayState == .idle)
  }

  @Test func unviewedPollingPreservesReadStateWithoutANewCompletion() {
    let (state, surfaceID) = makeViewedState()
    state.lastWindowIsKey = false
    let idle = PaneAgentState(state: .idle, seen: true)
    #expect(state.resolvedSeen(previous: idle, stabilized: .idle, surfaceID: surfaceID))
    let unread = PaneAgentState(state: .idle, seen: false)
    #expect(!state.resolvedSeen(previous: unread, stabilized: .blocked, surfaceID: surfaceID))
  }

  private func apply(_ condition: ViewingCondition, to state: WorktreeTerminalState) {
    switch condition {
    case .viewed: break
    case .inactive: state.lastWindowIsKey = false
    case .hidden: state.lastWindowIsVisible = false
    case .unknown:
      state.lastWindowIsKey = nil
      state.lastWindowIsVisible = nil
    case .canvas: state.isCanvasManaged = true
    case .otherWorktree: state.isSelected = { false }
    case .otherPane:
      if let tabID = state.tabManager.selectedTabId {
        state.focusedSurfaceIdByTab[tabID] = UUID()
      }
    case .otherTab:
      let tabID = state.tabManager.createTab(title: "other", icon: nil)
      state.tabManager.selectTab(tabID)
    }
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
}
