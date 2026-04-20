import ComposableArchitecture
import SwiftUI

/// Root view for Shelf presentation mode.
///
/// This is the Phase 1 stub; subsequent phases layer in the three-segment
/// spine stack, tab slots, animations, and context menus described in
/// `doc-onevcat/shelf-view.md`.
struct ShelfView: View {
  let store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "books.vertical")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("Shelf view")
        .font(.title2)
      Text("Phase 1 placeholder — spine stack and book content arrive in subsequent phases.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      if let worktree = store.selectedTerminalWorktree {
        Text("Current open book: \(worktree.name)")
          .font(.callout.monospaced())
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
  }
}
