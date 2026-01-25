import ComposableArchitecture

struct TerminalClient {
  var createTab: @MainActor @Sendable (Worktree) -> Void
  var closeFocusedTab: @MainActor @Sendable (Worktree) -> Bool
  var closeFocusedSurface: @MainActor @Sendable (Worktree) -> Bool
  var prune: @MainActor @Sendable (Set<Worktree.ID>) -> Void
}

extension TerminalClient: DependencyKey {
  static let liveValue = TerminalClient(
    createTab: { _ in fatalError("TerminalClient.createTab not configured") },
    closeFocusedTab: { _ in
      fatalError("TerminalClient.closeFocusedTab not configured")
    },
    closeFocusedSurface: { _ in
      fatalError("TerminalClient.closeFocusedSurface not configured")
    },
    prune: { _ in
      fatalError("TerminalClient.prune not configured")
    }
  )

  static let testValue = TerminalClient(
    createTab: { _ in },
    closeFocusedTab: { _ in false },
    closeFocusedSurface: { _ in false },
    prune: { _ in }
  )
}

extension DependencyValues {
  var terminalClient: TerminalClient {
    get { self[TerminalClient.self] }
    set { self[TerminalClient.self] = newValue }
  }
}
