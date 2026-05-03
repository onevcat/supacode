import ComposableArchitecture
import SwiftUI

struct SidebarListView: View {
  enum RepositoryListHeaderAction: Equatable {
    case expandAll
    case collapseAll

    var title: String {
      switch self {
      case .expandAll:
        return "Expand All"
      case .collapseAll:
        return "Collapse All"
      }
    }

    var systemImageName: String {
      "chevron.right"
    }

    var rotation: Angle {
      switch self {
      case .expandAll:
        return .zero
      case .collapseAll:
        return .degrees(90)
      }
    }
  }

  @Bindable var store: StoreOf<RepositoriesFeature>
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Binding var sidebarSelections: Set<SidebarSelection>
  let terminalManager: WorktreeTerminalManager
  @FocusState private var isSidebarFocused: Bool
  @State private var isDragActive = false
  @State private var targetedRepositoryDropDestination: Int?

  var body: some View {
    let state = store.state
    let hotkeyRows = state.orderedWorktreeRows(includingRepositoryIDs: expandedRepoIDs)
    let presentation = state.sidebarPresentation(expandedRepositoryIDs: expandedRepoIDs)
    let expandableRepositoryIDs = Self.expandableRepositoryIDs(in: state.repositories)
    let repositoryListHeaderAction = Self.repositoryListHeaderAction(
      expandedRepoIDs: expandedRepoIDs,
      expandableRepositoryIDs: expandableRepositoryIDs
    )
    let repositoryItems = presentation.items.filter(\.isRepositoryOrderItem)
    let showsRepositoryListHeader = presentation.items.contains { item in
      if case .listHeader = item {
        return true
      }
      return false
    }
    let selectedWorktreeIDs = Self.selectedWorktreeIDs(in: state)
    let pendingSidebarReveal = state.pendingSidebarReveal

    ScrollViewReader { scrollProxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if showsRepositoryListHeader {
            repositoryListHeader(
              action: repositoryListHeaderAction,
              expandableRepositoryIDs: expandableRepositoryIDs
            )
          }

          ForEach(Array(repositoryItems.enumerated()), id: \.element.id) { index, item in
            repositoryDropZone(
              destination: index,
              repositoryOrderIDs: presentation.repositoryOrderIDs
            )
            repositoryItemView(
              item,
              index: index,
              hotkeyRows: hotkeyRows,
              selectedWorktreeIDs: selectedWorktreeIDs
            )
          }
          repositoryDropZone(
            destination: repositoryItems.count,
            repositoryOrderIDs: presentation.repositoryOrderIDs
          )
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.never)
      .frame(minWidth: 220)
      .background(.bar)
      .onDragSessionUpdated { session in
        if case .ended = session.phase {
          endSidebarDrag()
          return
        }
        if case .dataTransferCompleted = session.phase {
          endSidebarDrag()
          return
        }
        beginSidebarDrag()
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
      .focused($isSidebarFocused)
      .task(id: pendingSidebarReveal?.id) {
        await revealPendingSidebarWorktree(pendingSidebarReveal, with: scrollProxy)
      }
    }  // ScrollViewReader
  }

  private func focusTerminalAfterSidebarSelection(worktreeID: Worktree.ID?) {
    guard let worktreeID else { return }
    Task { @MainActor [terminalManager] in
      for _ in 0..<4 {
        await Task.yield()
        if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
          terminalState.focusSelectedTab()
          return
        }
      }
    }
  }

  private func repositoryListHeader(
    action: RepositoryListHeaderAction,
    expandableRepositoryIDs: Set<Repository.ID>
  ) -> some View {
    HStack(spacing: 8) {
      Text("Repositories")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
      if !expandableRepositoryIDs.isEmpty {
        Button {
          withAnimation(.easeOut(duration: 0.2)) {
            switch action {
            case .expandAll:
              expandedRepoIDs.formUnion(expandableRepositoryIDs)
            case .collapseAll:
              expandedRepoIDs.subtract(expandableRepositoryIDs)
            }
          }
        } label: {
          Label(action.title, systemImage: action.systemImageName)
            .labelStyle(.iconOnly)
            .frame(width: 20, height: 20)
            .rotationEffect(action.rotation)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(action.title)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 26, alignment: .center)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private func repositoryItemView(
    _ item: SidebarItem,
    index: Int,
    hotkeyRows: [WorktreeRowModel],
    selectedWorktreeIDs: Set<Worktree.ID>
  ) -> some View {
    switch item {
    case .repository(let model):
      if let repository = store.state.repositories[id: model.repositoryID] {
        RepositorySectionView(
          repository: repository,
          hasTopSpacing: index > 0,
          isDragActive: isDragActive,
          hotkeyRows: hotkeyRows,
          selectedWorktreeIDs: selectedWorktreeIDs,
          expandedRepoIDs: $expandedRepoIDs,
          store: store,
          terminalManager: terminalManager,
          onRepositorySelected: {
            selectRepository(repository)
          }
        )
        .draggableRepository(
          id: model.repositoryID,
          isEnabled: !model.isRemoving,
          beginDrag: beginSidebarDrag
        )
      }

    case .failedRepository(let model):
      FailedRepositoryRow(
        name: model.name,
        path: model.path,
        showFailure: {
          let message = "\(model.path)\n\n\(model.failureMessage)"
          store.send(.presentAlert(title: "Unable to load \(model.name)", message: message))
        },
        removeRepository: {
          store.send(.repositoryManagement(.removeFailedRepository(model.id)))
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
      .draggableRepository(
        id: model.id,
        isEnabled: model.isReorderable,
        beginDrag: beginSidebarDrag
      )

    case .listHeader, .archivedWorktrees:
      EmptyView()
    }
  }

  private func repositoryDropZone(
    destination: Int,
    repositoryOrderIDs: [Repository.ID]
  ) -> some View {
    SidebarDropIndicator(isVisible: targetedRepositoryDropDestination == destination)
      .onDrop(
        of: [.prowlSidebarRepositoryID],
        delegate: SidebarRepositoryDropDelegate(
          destination: destination,
          repositoryOrderIDs: repositoryOrderIDs,
          targetedDestination: $targetedRepositoryDropDestination,
          onDrop: { offsets, destination in
            store.send(.worktreeOrdering(.repositoriesMoved(offsets, destination)))
          },
          onDragEnded: endSidebarDrag
        )
      )
  }

  private func beginSidebarDrag() {
    guard !isDragActive else { return }
    isDragActive = true
    store.send(.worktreeOrdering(.setSidebarDragActive(true)))
  }

  private func endSidebarDrag() {
    targetedRepositoryDropDestination = nil
    guard isDragActive else { return }
    isDragActive = false
    store.send(.worktreeOrdering(.setSidebarDragActive(false)))
  }

  private func selectRepository(_ repository: Repository) {
    if repository.capabilities.supportsWorktrees {
      withAnimation(.easeOut(duration: 0.2)) {
        if expandedRepoIDs.contains(repository.id) {
          expandedRepoIDs.remove(repository.id)
        } else {
          expandedRepoIDs.insert(repository.id)
        }
      }
      sidebarSelections = []
    } else {
      sidebarSelections = [.repository(repository.id)]
      store.send(.selectRepository(repository.id))
      focusTerminalAfterSidebarSelection(worktreeID: store.state.selectedTerminalWorktree?.id)
    }
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
      scrollProxy.scrollTo(SidebarScrollID.worktree(pendingSidebarReveal.worktreeID), anchor: .center)
    }
    store.send(.consumePendingSidebarReveal(pendingSidebarReveal.id))
  }

  static func expandableRepositoryIDs<Repositories: Sequence>(
    in repositories: Repositories
  ) -> Set<Repository.ID> where Repositories.Element == Repository {
    Set(
      repositories
        .filter(\.capabilities.supportsWorktrees)
        .map(\.id)
    )
  }

  static func repositoryListHeaderAction(
    expandedRepoIDs: Set<Repository.ID>,
    expandableRepositoryIDs: Set<Repository.ID>
  ) -> RepositoryListHeaderAction {
    !expandedRepoIDs.isDisjoint(with: expandableRepositoryIDs)
      ? .collapseAll
      : .expandAll
  }

  static func showsRepositoryListHeader(repositoryCount: Int) -> Bool {
    SidebarPresentation.showsListHeader(repositoryCount: repositoryCount)
  }

  static func selectedWorktreeIDs(in state: RepositoriesFeature.State) -> Set<Worktree.ID> {
    var selectedWorktreeIDs = state.sidebarSelectedWorktreeIDs
    if let selectedWorktreeID = state.selectedWorktreeID {
      selectedWorktreeIDs.insert(selectedWorktreeID)
    }
    return selectedWorktreeIDs
  }
}

extension SidebarItem {
  fileprivate var isRepositoryOrderItem: Bool {
    repositoryOrderID != nil
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
