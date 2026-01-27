import Observation

@MainActor
@Observable
final class WorktreeTerminalManager {
  private let runtime: GhosttyRuntime
  private var states: [Worktree.ID: WorktreeTerminalState] = [:]
  private var notificationsEnabled = true
  private var eventContinuation: AsyncStream<TerminalClient.Event>.Continuation?
  var selectedWorktreeID: Worktree.ID?

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
  }

  func handleCommand(_ command: TerminalClient.Command) {
    switch command {
    case .createTab(let worktree):
      createTab(in: worktree)
    case .closeFocusedTab(let worktree):
      _ = closeFocusedTab(in: worktree)
    case .closeFocusedSurface(let worktree):
      _ = closeFocusedSurface(in: worktree)
    case .startSearch(let worktree):
      state(for: worktree).performBindingActionOnFocusedSurface("start_search")
    case .searchSelection(let worktree):
      state(for: worktree).performBindingActionOnFocusedSurface("search_selection")
    case .navigateSearchNext(let worktree):
      state(for: worktree).performBindingActionOnFocusedSurface("navigate_search:next")
    case .navigateSearchPrevious(let worktree):
      state(for: worktree).performBindingActionOnFocusedSurface("navigate_search:previous")
    case .endSearch(let worktree):
      state(for: worktree).performBindingActionOnFocusedSurface("end_search")
    case .prune(let ids):
      prune(keeping: ids)
    case .setNotificationsEnabled(let enabled):
      setNotificationsEnabled(enabled)
    case .clearNotificationIndicator(let worktree):
      clearNotificationIndicator(for: worktree)
    case .setSelectedWorktreeID(let id):
      selectedWorktreeID = id
    }
  }

  func eventStream() -> AsyncStream<TerminalClient.Event> {
    eventContinuation?.finish()
    let (stream, continuation) = AsyncStream.makeStream(of: TerminalClient.Event.self)
    eventContinuation = continuation
    return stream
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
    state.setNotificationsEnabled(notificationsEnabled)
    state.isSelected = { [weak self] in
      self?.selectedWorktreeID == worktree.id
    }
    state.onNotificationReceived = { [weak self] title, body in
      self?.emit(.notificationReceived(worktreeID: worktree.id, title: title, body: body))
    }
    state.onTabCreated = { [weak self] in
      self?.emit(.tabCreated(worktreeID: worktree.id))
    }
    state.onTabClosed = { [weak self] in
      self?.emit(.tabClosed(worktreeID: worktree.id))
    }
    state.onFocusChanged = { [weak self] surfaceID in
      self?.emit(.focusChanged(worktreeID: worktree.id, surfaceID: surfaceID))
    }
    state.onTaskStatusChanged = { [weak self] status in
      self?.emit(.taskStatusChanged(worktreeID: worktree.id, status: status))
    }
    states[worktree.id] = state
    return state
  }

  func createTab(in worktree: Worktree) {
    let state = state(for: worktree)
    _ = state.createTab()
  }

  @discardableResult
  func closeFocusedTab(in worktree: Worktree) -> Bool {
    let state = state(for: worktree)
    return state.closeFocusedTab()
  }

  @discardableResult
  func closeFocusedSurface(in worktree: Worktree) -> Bool {
    let state = state(for: worktree)
    return state.closeFocusedSurface()
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

  func stateIfExists(for worktreeID: Worktree.ID) -> WorktreeTerminalState? {
    states[worktreeID]
  }

  func focusedTaskStatus(for worktreeID: Worktree.ID) -> WorktreeTaskStatus? {
    states[worktreeID]?.focusedTaskStatus
  }

  func setNotificationsEnabled(_ enabled: Bool) {
    notificationsEnabled = enabled
    for state in states.values {
      state.setNotificationsEnabled(enabled)
    }
  }

  func hasUnseenNotifications(for worktreeID: Worktree.ID) -> Bool {
    states[worktreeID]?.hasUnseenNotification == true
  }

  func clearNotificationIndicator(for worktree: Worktree) {
    states[worktree.id]?.clearNotificationIndicator()
  }

  private func emit(_ event: TerminalClient.Event) {
    eventContinuation?.yield(event)
  }
}
