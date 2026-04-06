import ComposableArchitecture
import SwiftUI

struct SidebarListView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Binding var sidebarSelections: Set<SidebarSelection>
  let terminalManager: WorktreeTerminalManager
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
    List(selection: selection) {
      if orderedRoots.isEmpty {
        let repositories = store.repositories
        ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repository in
          RepositorySectionView(
            repository: repository,
            showsTopSeparator: index > 0,
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
              showsTopSeparator: index > 0,
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
      CanvasSidebarButton(
        store: store,
        isSelected: state.isShowingCanvas
      )
      .padding(.top, 4)
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
  }
}

// MARK: - Previews

/// Composed sidebar preview using leaf views only (no TCA store or GhosttyRuntime needed).
@MainActor
private struct SidebarLayoutPreview: View {
  @State private var hoveredID: String?

  var body: some View {
    List {
      sectionHeader(name: "supacode", tabCount: 4)
      row(id: "sc-main", name: "main", worktreeName: "Default", isMainWorktree: true)
      row(
        id: "sc-sidebar", name: "feature/sidebar-redesign", worktreeName: "sidebar-redesign",
        addedLines: 120, removedLines: 45
      )
      row(id: "sc-pinned", name: "feature/auth", worktreeName: "auth", isPinned: true)
      row(id: "sc-running", name: "fix/crash", worktreeName: "crash", taskStatus: .running)

      sectionHeader(name: "ghostty", tabCount: 1, isFirst: false)
      row(id: "gh-main", name: "main", worktreeName: "Default", isMainWorktree: true)
      row(id: "gh-feat", name: "feature/renderer", worktreeName: "renderer", isLoading: true)
    }
    .listStyle(.sidebar)
    .scrollIndicators(.never)
    .frame(width: 280, height: 500)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Label("Add Repository", systemImage: "folder.badge.plus")
          .font(.callout)
        Spacer()
        Image(systemName: "questionmark.circle")
        Image(systemName: "arrow.clockwise")
        Image(systemName: "archivebox")
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color(nsColor: .windowBackgroundColor))
      .overlay(alignment: .top) { Divider() }
    }
  }

  private func sectionHeader(
    name: String,
    tabCount: Int,
    isFirst: Bool = true
  ) -> some View {
    HStack {
      RepoHeaderRow(name: name, isRemoving: false, tabCount: tabCount)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 28, alignment: .center)
    .padding(.top, isFirst ? 0 : 8)
    .listRowInsets(EdgeInsets())
    .listRowSeparator(.hidden)
  }

  private func row(
    id: String,
    name: String,
    worktreeName: String,
    isPinned: Bool = false,
    isMainWorktree: Bool = false,
    isLoading: Bool = false,
    taskStatus: WorktreeTaskStatus? = nil,
    addedLines: Int? = nil,
    removedLines: Int? = nil
  ) -> some View {
    let info: WorktreeInfoEntry? =
      if let addedLines, let removedLines {
        WorktreeInfoEntry(addedLines: addedLines, removedLines: removedLines, pullRequest: nil)
      } else {
        nil
      }
    let isHovered = hoveredID == id
    return WorktreeRow(
      name: name,
      worktreeName: worktreeName,
      info: info,
      showsPullRequestInfo: false,
      isHovered: isHovered,
      isPinned: isPinned,
      isMainWorktree: isMainWorktree,
      isLoading: isLoading,
      taskStatus: taskStatus,
      isRunScriptRunning: false,
      showsNotificationIndicator: false,
      notifications: [],
      onFocusNotification: { _ in },
      shortcutHint: nil,
      pinAction: {},
      isSelected: false,
      archiveAction: {},
      onDiffTap: addedLines != nil ? {} : nil
    )
    .listRowInsets(EdgeInsets())
    .listRowSeparator(.hidden)
    .onHover { hovering in
      hoveredID = hovering ? id : nil
    }
  }
}

#Preview("Sidebar Layout") {
  SidebarLayoutPreview()
}
