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
          onSplitHorizontal: isOpen(book) ? { performSplit(direction: "new_split:down") } : nil
        )
      }
    }
  }

  private func performSplit(direction: String) {
    guard let openID = store.state.openShelfBookID,
      let state = terminalManager.stateIfExists(for: openID)
    else { return }
    _ = state.performBindingActionOnFocusedSurface(direction)
  }

  private func isOpen(_ book: ShelfBook) -> Bool {
    store.state.openShelfBookID == book.id
  }

  @ViewBuilder
  private func openBookArea(for book: ShelfBook, state: RepositoriesFeature.State) -> some View {
    if let worktree = state.selectedTerminalWorktree, worktree.id == book.id {
      ShelfOpenBookView(
        worktree: worktree,
        manager: terminalManager,
        shouldRunSetupScript: state.pendingSetupScriptWorktreeIDs.contains(worktree.id)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(worktree.id)
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
