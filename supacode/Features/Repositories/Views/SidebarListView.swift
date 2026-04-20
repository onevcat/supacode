import ComposableArchitecture
import SwiftUI

struct SidebarListView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Binding var sidebarSelections: Set<SidebarSelection>
  let terminalManager: WorktreeTerminalManager
  @FocusState private var isSidebarFocused: Bool
  @State private var isDragActive = false

  var body: some View {
    let state = store.state
    let hotkeyRows = state.orderedWorktreeRows(includingRepositoryIDs: expandedRepoIDs)
    let orderedRoots = state.orderedRepositoryRoots()
    let selectedWorktreeIDs = Set(sidebarSelections.compactMap(\.worktreeID))
    let selection = Binding<Set<SidebarSelection>>(
      get: {
        var nextSelections = sidebarSelections
        if state.isShowingCanvas {
          nextSelections = [.canvas]
        } else if state.isShowingArchivedWorktrees {
          nextSelections = [.archivedWorktrees]
        } else {
          nextSelections.remove(.archivedWorktrees)
          nextSelections.remove(.canvas)
          if let selectedRepository = state.selectedRepository, selectedRepository.kind == .plain {
            nextSelections = [.repository(selectedRepository.id)]
          } else if let selectedWorktreeID = state.selectedWorktreeID {
            nextSelections.insert(.worktree(selectedWorktreeID))
          }
        }
        return nextSelections
      },
      set: { newValue in
        let nextSelections = newValue
        let repositorySelections: [Repository.ID] = nextSelections.compactMap { selection in
          guard case .repository(let repositoryID) = selection else { return nil }
          return repositoryID
        }

        if nextSelections.contains(.canvas) {
          sidebarSelections = [.canvas]
          store.send(.selectCanvas)
          return
        }

        if nextSelections.contains(.archivedWorktrees) {
          sidebarSelections = [.archivedWorktrees]
          store.send(.selectArchivedWorktrees)
          return
        }

        if let repositoryID = repositorySelections.first {
          guard let repository = state.repositories[id: repositoryID] else {
            return
          }
          if repository.capabilities.supportsWorktrees {
            withAnimation(.easeOut(duration: 0.2)) {
              if expandedRepoIDs.contains(repositoryID) {
                expandedRepoIDs.remove(repositoryID)
              } else {
                expandedRepoIDs.insert(repositoryID)
              }
            }
            sidebarSelections = []
          } else {
            sidebarSelections = [.repository(repositoryID)]
            store.send(.selectRepository(repositoryID))
          }
          return
        }

        let worktreeIDs = Set(nextSelections.compactMap(\.worktreeID))
        guard !worktreeIDs.isEmpty else {
          sidebarSelections = []
          store.send(.selectWorktree(nil))
          return
        }
        sidebarSelections = Set(worktreeIDs.map(SidebarSelection.worktree))
        if let selectedWorktreeID = state.selectedWorktreeID, worktreeIDs.contains(selectedWorktreeID) {
          return
        }
        let nextPrimarySelection =
          hotkeyRows.map(\.id).first(where: worktreeIDs.contains)
          ?? worktreeIDs.first
        store.send(.selectWorktree(nextPrimarySelection, focusTerminal: true))
      }
    )
    let repositoriesByID = Dictionary(uniqueKeysWithValues: store.repositories.map { ($0.id, $0) })
    let pendingSidebarReveal = state.pendingSidebarReveal

    ScrollViewReader { scrollProxy in
      List(selection: selection) {
        if orderedRoots.isEmpty {
          let repositories = store.repositories
          ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repository in
            RepositorySectionView(
              repository: repository,
              hasTopSpacing: index > 0,
              isDragActive: isDragActive,
              hotkeyRows: hotkeyRows,
              selectedWorktreeIDs: selectedWorktreeIDs,
              expandedRepoIDs: $expandedRepoIDs,
              store: store,
              terminalManager: terminalManager
            )
            .listRowInsets(EdgeInsets())
          }
        } else {
          let orderedRows = Array(orderedRoots.enumerated()).map { index, rootURL in
            (
              index: index,
              rootURL: rootURL,
              repositoryID: rootURL.standardizedFileURL.path(percentEncoded: false)
            )
          }
          ForEach(orderedRows, id: \.repositoryID) { row in
            let index = row.index
            let rootURL = row.rootURL
            let repositoryID = row.repositoryID
            if let failureMessage = state.loadFailuresByID[repositoryID] {
              let name = Repository.name(for: rootURL.standardizedFileURL)
              let path = rootURL.standardizedFileURL.path(percentEncoded: false)
              FailedRepositoryRow(
                name: name,
                path: path,
                showFailure: {
                  let message = "\(path)\n\n\(failureMessage)"
                  store.send(.presentAlert(title: "Unable to load \(name)", message: message))
                },
                removeRepository: {
                  store.send(.repositoryManagement(.removeFailedRepository(repositoryID)))
                }
              )
              .padding(.horizontal, 12)
              .overlay(alignment: .top) {
                if index > 0 {
                  Rectangle()
                    .fill(.secondary)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
              }
              .listRowInsets(EdgeInsets())
            } else if let repository = repositoriesByID[repositoryID] {
              RepositorySectionView(
                repository: repository,
                hasTopSpacing: index > 0,
                isDragActive: isDragActive,
                hotkeyRows: hotkeyRows,
                selectedWorktreeIDs: selectedWorktreeIDs,
                expandedRepoIDs: $expandedRepoIDs,
                store: store,
                terminalManager: terminalManager
              )
              .listRowInsets(EdgeInsets())
            }
          }
          .onMove { offsets, destination in
            store.send(.worktreeOrdering(.repositoriesMoved(offsets, destination)))
          }
        }
      }
      .listStyle(.sidebar)
      .scrollIndicators(.never)
      .frame(minWidth: 220)
      .onDragSessionUpdated { session in
        if case .ended = session.phase {
          if isDragActive {
            isDragActive = false
          }
          return
        }
        if case .dataTransferCompleted = session.phase {
          if isDragActive {
            isDragActive = false
          }
          return
        }
        if !isDragActive {
          isDragActive = true
        }
      }
      .safeAreaInset(edge: .top) {
        HStack(spacing: 4) {
          CanvasSidebarButton(
            store: store,
            isSelected: state.isShowingCanvas
          )
          ShelfSidebarButton(
            store: store,
            isSelected: state.isShowingShelf
          )
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .background(.bar)
        .overlay(alignment: .bottom) {
          Divider()
        }
      }
      .safeAreaInset(edge: .bottom) {
        SidebarFooterView(store: store)
      }
      .dropDestination(for: URL.self) { urls, _ in
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        store.send(.repositoryManagement(.openRepositories(fileURLs)))
        return true
      }
      .onKeyPress { keyPress in
        guard !keyPress.characters.isEmpty else { return .ignored }
        let isNavigationKey =
          keyPress.key == .upArrow
          || keyPress.key == .downArrow
          || keyPress.key == .leftArrow
          || keyPress.key == .rightArrow
          || keyPress.key == .home
          || keyPress.key == .end
          || keyPress.key == .pageUp
          || keyPress.key == .pageDown
        if isNavigationKey { return .ignored }
        let hasCommandModifier = keyPress.modifiers.contains(.command)
        if hasCommandModifier { return .ignored }
        guard let worktreeID = store.selectedWorktreeID,
          state.sidebarSelectedWorktreeIDs.count == 1,
          state.sidebarSelectedWorktreeIDs.contains(worktreeID),
          let terminalState = terminalManager.stateIfExists(for: worktreeID)
        else { return .ignored }
        terminalState.focusAndInsertText(keyPress.characters)
        return .handled
      }
      .focused($isSidebarFocused)
      .task(id: pendingSidebarReveal?.id) {
        await revealPendingSidebarWorktree(pendingSidebarReveal, with: scrollProxy)
      }
    }  // ScrollViewReader
  }

  @MainActor
  private func revealPendingSidebarWorktree(
    _ pendingSidebarReveal: PendingSidebarReveal?,
    with scrollProxy: ScrollViewProxy
  ) async {
    guard let pendingSidebarReveal else { return }
    // Give SwiftUI time to materialize newly expanded section rows before scrolling.
    await Task.yield()
    await Task.yield()
    isSidebarFocused = true
    withAnimation(.easeOut(duration: 0.2)) {
      scrollProxy.scrollTo(pendingSidebarReveal.worktreeID, anchor: .center)
    }
    store.send(.consumePendingSidebarReveal(pendingSidebarReveal.id))
  }
}

// MARK: - Previews

#if DEBUG
  @MainActor
  private struct SidebarLayoutPreview: View {
    @State private var expandedRepoIDs: Set<Repository.ID>
    @State private var sidebarSelections: Set<SidebarSelection> = []
    private let store: StoreOf<RepositoriesFeature>
    private let terminalManager: WorktreeTerminalManager = .preview

    init() {
      let state = Self.mockState
      _expandedRepoIDs = State(initialValue: Set(state.repositories.map(\.id)))
      store = Store(initialState: state) { EmptyReducer() }
    }

    var body: some View {
      SidebarListView(
        store: store,
        expandedRepoIDs: $expandedRepoIDs,
        sidebarSelections: $sidebarSelections,
        terminalManager: terminalManager
      )
      .environment(CommandKeyObserver())
      .frame(width: 280, height: 500)
    }

    private static var mockState: RepositoriesFeature.State {
      let repo1Root = URL(fileURLWithPath: "/tmp/supacode")
      let repo1Worktrees: IdentifiedArrayOf<Worktree> = [
        Worktree(
          id: repo1Root.path, name: "main", detail: ".",
          workingDirectory: repo1Root, repositoryRootURL: repo1Root
        ),
        Worktree(
          id: "/tmp/wt/sidebar", name: "feature/sidebar-redesign", detail: "/tmp/wt/sidebar",
          workingDirectory: URL(fileURLWithPath: "/tmp/wt/sidebar"), repositoryRootURL: repo1Root
        ),
        Worktree(
          id: "/tmp/wt/auth", name: "feature/auth", detail: "/tmp/wt/auth",
          workingDirectory: URL(fileURLWithPath: "/tmp/wt/auth"), repositoryRootURL: repo1Root
        ),
        Worktree(
          id: "/tmp/wt/crash", name: "fix/crash", detail: "/tmp/wt/crash",
          workingDirectory: URL(fileURLWithPath: "/tmp/wt/crash"), repositoryRootURL: repo1Root
        ),
      ]
      let repo1 = Repository(
        id: repo1Root.path, rootURL: repo1Root, name: "supacode", worktrees: repo1Worktrees
      )

      let repo2Root = URL(fileURLWithPath: "/tmp/ghostty")
      let repo2Worktrees: IdentifiedArrayOf<Worktree> = [
        Worktree(
          id: repo2Root.path, name: "main", detail: ".",
          workingDirectory: repo2Root, repositoryRootURL: repo2Root
        ),
        Worktree(
          id: "/tmp/wt/renderer", name: "feature/renderer", detail: "/tmp/wt/renderer",
          workingDirectory: URL(fileURLWithPath: "/tmp/wt/renderer"), repositoryRootURL: repo2Root
        ),
      ]
      let repo2 = Repository(
        id: repo2Root.path, rootURL: repo2Root, name: "ghostty", worktrees: repo2Worktrees
      )

      var state = RepositoriesFeature.State()
      state.repositories = [repo1, repo2]
      state.pinnedWorktreeIDs = ["/tmp/wt/auth"]
      state.worktreeInfoByID = [
        "/tmp/wt/sidebar": WorktreeInfoEntry(addedLines: 120, removedLines: 45, pullRequest: nil)
      ]
      return state
    }
  }

  #Preview("Sidebar Layout") {
    SidebarLayoutPreview()
  }
#endif
