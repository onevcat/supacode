import Foundation

enum CanvasInitialFocusResolver {
  struct Candidate: Equatable, Sendable {
    let worktreeID: Worktree.ID
    let tabID: TerminalTabID
    let focusedSurfaceID: UUID
    let isSelectedTab: Bool
  }

  struct Focus: Equatable, Sendable {
    let tabID: TerminalTabID
    let surfaceID: UUID
  }

  static func initialFocus(
    preferredSurfaceID: UUID?,
    preferredWorktreeID: Worktree.ID?,
    candidates: [Candidate]
  ) -> Focus? {
    if let preferredSurfaceID,
      let candidate = candidates.first(where: { $0.focusedSurfaceID == preferredSurfaceID })
    {
      return Focus(tabID: candidate.tabID, surfaceID: candidate.focusedSurfaceID)
    }

    if let preferredWorktreeID,
      let candidate = candidates.first(where: { $0.worktreeID == preferredWorktreeID && $0.isSelectedTab })
    {
      return Focus(tabID: candidate.tabID, surfaceID: candidate.focusedSurfaceID)
    }

    return candidates.first.map { Focus(tabID: $0.tabID, surfaceID: $0.focusedSurfaceID) }
  }
}
