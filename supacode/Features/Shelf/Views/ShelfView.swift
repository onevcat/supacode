import ComposableArchitecture
import SwiftUI

private let shelfLogger = SupaLogger("Shelf")

/// Root view for Shelf presentation mode.
///
/// Phase 3 layout: three horizontal segments — a left stack of passed
/// spines (each showing its book's tabs), the currently open book's
/// terminal area, and a right stack of upcoming spines. Clicking a tab
/// on any spine opens that book (when different) and selects that tab.
/// Animations and the ⌘-held digit overlay are layered in subsequent
/// phases.
struct ShelfView: View {
  let store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  let createTab: () -> Void

  /// Mirrors the Ghostty `background-opacity` setting so the Shelf can
  /// honor the same window transparency as normal view mode. A previous
  /// plain `.background(.background)` defeated transparency entirely by
  /// stamping an opaque layer behind every child — including the
  /// terminal surface and empty-state area.
  @Environment(\.surfaceBackgroundOpacity) private var surfaceBackgroundOpacity

  var body: some View {
    // Body-invocation counter. The @ViewBuilder getter rules out a
    // `defer`-based interval, but a fire-and-forget event marker is a
    // simple expression and has no impact on the rendered tree. Each
    // marker corresponds to one full body re-evaluation — useful for
    // sanity-checking how often the root re-renders during animation.
    let _ = shelfLogger.event("ShelfView.body")
    let state = store.state
    let books = state.orderedShelfBooks()
    let openBookID = state.openShelfBookID
    let openIndex = openBookID.flatMap { id in
      books.firstIndex(where: { $0.id == id })
    }

    HStack(spacing: 0) {
      ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
        spine(book: book, index: index, openIndex: openIndex)
        if book.id == openBookID {
          openBookArea(for: book, state: state)
            .transition(.opacity)
        }
      }
      if openBookID == nil {
        emptyOpenArea()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor).opacity(surfaceBackgroundOpacity))
    // Animate on every openBookID change — covers both Shelf-originated
    // book switches (which also set their own TCA animation) and
    // left-nav-originated switches, so the spine flow is consistent
    // regardless of entry point.
    .animation(.easeInOut(duration: 0.2), value: openBookID)
  }

  @ViewBuilder
  private func spine(book: ShelfBook, index: Int, openIndex: Int?) -> some View {
    let distance = openIndex.map { abs(index - $0) }
    let open = index == openIndex
    ShelfSpineView(
      book: book,
      isOpen: open,
      distanceFromOpen: distance,
      terminalState: terminalManager.stateIfExists(for: book.id),
      onOpenBook: { openBook(book, selectingTab: nil) },
      onSelectTab: { tabID in openBook(book, selectingTab: tabID) },
      onNewTab: {
        // On a closed spine, `+` doubles as "pull this book out and
        // start a fresh tab". Sequencing is fine because TCA runs
        // reducers synchronously — `newTerminal` will observe the
        // new `selectedTerminalWorktree` set by `selectWorktree`.
        switchToBookIfNeeded(book)
        createTab()
      },
      onSplitVertical: open ? { performSplit(direction: "new_split:right") } : nil,
      onSplitHorizontal: open ? { performSplit(direction: "new_split:down") } : nil,
      closeMenuTitle: closeMenuTitle(for: book),
      onCloseBook: { closeBook(book) },
      onOpenRepositorySettings: {
        store.send(.repositoryManagement(.openRepositorySettings(book.repositoryID)))
      }
    )
  }

  /// Dispatch the open-book action only when `book` isn't already the open
  /// one — idempotent helper for taps that imply a book change.
  ///
  /// No `animation:` is passed to `store.send` because the visible
  /// spine-flow animation is already driven by the view-level
  /// `.animation(.easeInOut(duration: 0.2), value: openBookID)` modifier
  /// on the root container — wrapping the dispatch in another animation
  /// transaction would double-run layout / transition machinery for the
  /// same change.
  private func switchToBookIfNeeded(_ book: ShelfBook) {
    guard !isOpen(book) else { return }
    shelfLogger.event("BookClick.NewTabSpine")
    switch book.kind {
    case .worktree:
      store.send(.selectWorktree(book.id, focusTerminal: true))
    case .plainFolder:
      store.send(.selectRepository(book.repositoryID))
    }
  }

  private func performSplit(direction: String) {
    guard let openID = store.state.openShelfBookID,
      let state = terminalManager.stateIfExists(for: openID)
    else { return }
    _ = state.performBindingActionOnFocusedSurface(direction)
  }

  /// "Close Worktree / Close Folder" context action. Equivalent to
  /// closing the last tab on this book: tears down all of its terminal
  /// tabs, which lets the existing `tabClosed(remainingTabs: 0)` →
  /// `markWorktreeClosed` pipeline retire the book from the Shelf and
  /// auto-advance selection. Intentionally does *not* archive the
  /// worktree or remove the repository — Shelf removal is a view-state
  /// concern, not a destructive resource operation.
  private func closeBook(_ book: ShelfBook) {
    if let state = terminalManager.stateIfExists(for: book.id), !state.tabManager.tabs.isEmpty {
      state.closeAllTabs()
    } else {
      // No live tabs to fall through the closeAllTabs → tabClosed
      // pipeline — drive the Shelf removal directly.
      store.send(.markWorktreeClosed(book.id))
    }
  }

  private func closeMenuTitle(for book: ShelfBook) -> String {
    switch book.kind {
    case .worktree: "Close Worktree"
    case .plainFolder: "Close Folder"
    }
  }

  private func isOpen(_ book: ShelfBook) -> Bool {
    store.state.openShelfBookID == book.id
  }

  @ViewBuilder
  private func openBookArea(for book: ShelfBook, state: RepositoriesFeature.State) -> some View {
    if let worktree = state.selectedTerminalWorktree, worktree.id == book.id {
      let shouldFocus = state.shouldFocusTerminal(for: worktree.id)
      ShelfOpenBookView(
        worktree: worktree,
        manager: terminalManager,
        shouldRunSetupScript: state.pendingSetupScriptWorktreeIDs.contains(worktree.id),
        forceAutoFocus: shouldFocus
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(worktree.id)
      .onAppear {
        if shouldFocus {
          store.send(.worktreeCreation(.consumeTerminalFocus(worktree.id)))
        }
      }
    } else {
      emptyOpenArea()
    }
  }

  @ViewBuilder
  private func emptyOpenArea() -> some View {
    VStack(spacing: 10) {
      Image(systemName: "books.vertical")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("No worktree selected")
        .font(.headline)
      Text("Click a worktree to open it.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Open `book` and optionally select a specific tab on it. For the open
  /// book's own tab slots (no book change), this skips the worktree
  /// re-selection and just tells the tab manager to switch tab.
  private func openBook(_ book: ShelfBook, selectingTab tabID: TerminalTabID?) {
    let isAlreadyOpen = store.state.openShelfBookID == book.id
    if let tabID, isAlreadyOpen, let state = terminalManager.stateIfExists(for: book.id) {
      shelfLogger.event("BookClick.TabSwitchSameBook")
      state.tabManager.selectTab(tabID)
      return
    }
    shelfLogger.event("BookClick.SwitchBook")
    // The spine flow / terminal crossfade animation is already driven
    // by the view-level `.animation(_:value: openBookID)` on the root
    // container (~200ms ease-in-out per the Shelf design doc), so the
    // dispatch itself does not pass an `animation:` argument here.
    switch book.kind {
    case .worktree:
      store.send(.selectWorktree(book.id, focusTerminal: true))
    case .plainFolder:
      store.send(.selectRepository(book.repositoryID))
    }
    if let tabID {
      // Apply tab selection eagerly; the target book's state already exists
      // if the user has opened it before. For first-time opens the tab
      // manager seeds a default tab which we won't override.
      terminalManager.stateIfExists(for: book.id)?.tabManager.selectTab(tabID)
    }
  }
}
