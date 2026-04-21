import ComposableArchitecture
import SwiftUI

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

  /// Shared namespace so each spine's `matchedGeometryEffect` can bridge
  /// the left-stack ForEach and the right-stack ForEach without breaking
  /// visual identity while it moves between them.
  @Namespace private var spineNamespace

  var body: some View {
    let state = store.state
    let books = state.orderedShelfBooks()
    let openBookID = state.openShelfBookID
    let openIndex = openBookID.flatMap { id in
      books.firstIndex(where: { $0.id == id })
    }

    HStack(spacing: 0) {
      if let openIndex {
        spineStack(books: Array(books[0...openIndex]))
        openBookArea(for: books[openIndex], state: state)
          .transition(.opacity)
        let rightStart = openIndex + 1
        if rightStart < books.count {
          spineStack(books: Array(books[rightStart..<books.count]))
        }
      } else {
        spineStack(books: books)
        emptyOpenArea()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    // Animate on every openBookID change — covers both Shelf-originated
    // book switches (which also set their own TCA animation) and
    // left-nav-originated switches, so the spine flow is consistent
    // regardless of entry point.
    .animation(.easeInOut(duration: 0.2), value: openBookID)
  }

  @ViewBuilder
  private func spineStack(books: [ShelfBook]) -> some View {
    HStack(spacing: 0) {
      ForEach(books) { book in
        ShelfSpineView(
          book: book,
          isOpen: isOpen(book),
          terminalState: terminalManager.stateIfExists(for: book.id),
          onOpenBook: { openBook(book, selectingTab: nil) },
          onSelectTab: { tabID in openBook(book, selectingTab: tabID) },
          onNewTab: isOpen(book) ? createTab : nil,
          onSplitVertical: isOpen(book) ? { performSplit(direction: "new_split:right") } : nil,
          onSplitHorizontal: isOpen(book) ? { performSplit(direction: "new_split:down") } : nil,
          onRemoveBook: { removeBook(book) }
        )
        .matchedGeometryEffect(id: book.id, in: spineNamespace)
      }
    }
  }

  private func performSplit(direction: String) {
    guard let openID = store.state.openShelfBookID,
      let state = terminalManager.stateIfExists(for: openID)
    else { return }
    _ = state.performBindingActionOnFocusedSurface(direction)
  }

  /// "Remove Book" context action. Worktree books funnel through the
  /// existing archive flow (which shows confirmation + progress); plain
  /// folder books go through repository removal. Both pathways
  /// eventually drop the book off the Shelf via the same prune logic
  /// that drives the left navigation.
  private func removeBook(_ book: ShelfBook) {
    switch book.kind {
    case .worktree:
      store.send(.worktreeLifecycle(.requestArchiveWorktree(book.id, book.repositoryID)))
    case .plainFolder:
      store.send(.repositoryManagement(.requestRemoveRepository(book.repositoryID)))
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
      Text("No book selected")
        .font(.headline)
      Text("Click a spine to open a book.")
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
      state.tabManager.selectTab(tabID)
      return
    }
    // Animate the spine flow and terminal crossfade. The duration and
    // curve mirror the Shelf design doc: ~200ms ease-in-out, snappy but
    // legible so the user can read each spine's movement.
    switch book.kind {
    case .worktree:
      store.send(.selectWorktree(book.id, focusTerminal: true), animation: .easeInOut(duration: 0.2))
    case .plainFolder:
      store.send(.selectRepository(book.repositoryID), animation: .easeInOut(duration: 0.2))
    }
    if let tabID {
      // Apply tab selection eagerly; the target book's state already exists
      // if the user has opened it before. For first-time opens the tab
      // manager seeds a default tab which we won't override.
      terminalManager.stateIfExists(for: book.id)?.tabManager.selectTab(tabID)
    }
  }
}
