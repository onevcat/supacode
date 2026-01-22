import Bonsplit
import Observation

@MainActor
@Observable
final class WorktreeTerminalStore {
  private let runtime: GhosttyRuntime
  private var states: [Worktree.ID: WorktreeTerminalState] = [:]

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
  }

  func state(
    for worktree: Worktree,
    runSetupScriptIfNew: () -> Bool = { false }
  ) -> WorktreeTerminalState {
    if let existing = states[worktree.id] {
      return existing
    }
    let runSetupScript = runSetupScriptIfNew()
    let state = WorktreeTerminalState(
      runtime: runtime,
      worktree: worktree,
      runSetupScript: runSetupScript
    )
    states[worktree.id] = state
    return state
  }

  @discardableResult
  func createTab(in worktree: Worktree, pane: PaneID? = nil) -> TabID? {
    let state = state(for: worktree)
    return state.createTab(in: pane)
  }

  @discardableResult
  func closeFocusedTab(in worktree: Worktree) -> Bool {
    let state = state(for: worktree)
    return state.closeFocusedTab()
  }

  func prune(keeping worktreeIDs: Set<Worktree.ID>) {
    var removed: [WorktreeTerminalState] = []
    for (id, state) in states where !worktreeIDs.contains(id) {
      removed.append(state)
    }
    for state in removed {
      state.closeAllSurfaces()
    }
    states = states.filter { worktreeIDs.contains($0.key) }
  }
}
