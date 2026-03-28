import ComposableArchitecture
import SwiftUI

struct SidebarListView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  var body: some View {
    let state = store.state
    let expandedRepoIDs = state.expandedRepositoryIDs
    let hotkeyRows = state.orderedWorktreeRows(includingRepositoryIDs: expandedRepoIDs)
    let orderedRoots = state.orderedRepositoryRoots()
    let selectedWorktreeIDs = state.sidebarSelectedWorktreeIDs
    let currentSelections = state.sidebarSelections
    let selection = Binding<Set<SidebarSelection>>(
      get: { currentSelections },
      set: { newValue in
        guard newValue != currentSelections else { return }
        store.send(.selectionChanged(newValue))
      }
    )
    let repositoriesByID = Dictionary(uniqueKeysWithValues: store.repositories.map { ($0.id, $0) })
    List(selection: selection) {
      if orderedRoots.isEmpty {
        ForEach(store.repositories) { repository in
          SidebarRepositorySectionView(
            repository: repository,
            hotkeyRows: hotkeyRows,
            selectedWorktreeIDs: selectedWorktreeIDs,
            store: store,
            terminalManager: terminalManager
          )
        }
      } else {
        ForEach(sidebarRootRows(from: orderedRoots), id: \.repositoryID) { row in
          if let failureMessage = state.loadFailuresByID[row.repositoryID] {
            SidebarFailedRepositoryRow(
              rootURL: row.rootURL,
              failureMessage: failureMessage,
              store: store
            )
          } else if let repository = repositoriesByID[row.repositoryID] {
            SidebarRepositorySectionView(
              repository: repository,
              hotkeyRows: hotkeyRows,
              selectedWorktreeIDs: selectedWorktreeIDs,
              store: store,
              terminalManager: terminalManager
            )
          }
        }
        .onMove { offsets, destination in
          store.send(.repositoriesMoved(offsets, destination))
        }
      }
    }
    .listStyle(.sidebar)
    .scrollIndicators(.never)
    .frame(minWidth: 220)
    .dropDestination(for: URL.self) { urls, _ in
      let fileURLs = urls.filter(\.isFileURL)
      guard !fileURLs.isEmpty else { return false }
      store.send(.openRepositories(fileURLs))
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

  private func sidebarRootRows(
    from orderedRoots: [URL]
  ) -> [(rootURL: URL, repositoryID: Repository.ID)] {
    orderedRoots.map { rootURL in
      (
        rootURL: rootURL,
        repositoryID: rootURL.standardizedFileURL.path(percentEncoded: false)
      )
    }
  }
}

private struct SidebarRepositorySectionView: View {
  let repository: Repository
  let hotkeyRows: [WorktreeRowModel]
  let selectedWorktreeIDs: Set<Worktree.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  var body: some View {
    let isRemovingRepository = store.state.isRemovingRepository(repository)
    Section(isExpanded: repositoryExpansionBinding) {
      WorktreeRowsView(
        repository: repository,
        hotkeyRows: hotkeyRows,
        selectedWorktreeIDs: selectedWorktreeIDs,
        store: store,
        terminalManager: terminalManager
      )
    } header: {
      RepoSectionHeaderView(
        name: repository.name,
        isRemoving: isRemovingRepository
      )
    }
    .sectionActions {
      SidebarRepositorySectionActionsView(
        repositoryID: repository.id,
        isRemovingRepository: isRemovingRepository,
        store: store
      )
    }
  }

  private var repositoryExpansionBinding: Binding<Bool> {
    Binding(
      get: { store.state.isRepositoryExpanded(repository.id) },
      set: { isExpanded in
        store.send(.repositoryExpansionChanged(repository.id, isExpanded: isExpanded))
      }
    )
  }
}

private struct SidebarRepositorySectionActionsView: View {
  let repositoryID: Repository.ID
  let isRemovingRepository: Bool
  let store: StoreOf<RepositoriesFeature>

  var body: some View {
    Menu {
      Button("Repository Settings…", systemImage: "gear") {
        store.send(.openRepositorySettings(repositoryID))
      }
      .help("Repository Settings")
      Divider()
      Button("Remove Repository…", systemImage: "folder.badge.minus", role: .destructive) {
        store.send(.requestRemoveRepository(repositoryID))
      }
      .help("Remove Repository")
      .disabled(isRemovingRepository)
    } label: {
      Image(systemName: "ellipsis")
        .accessibilityLabel("Options")
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)

    Button {
      store.send(.createRandomWorktreeInRepository(repositoryID))
    } label: {
      Image(systemName: "plus")
        .accessibilityLabel("New Worktree")
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isRemovingRepository)
    .foregroundStyle(.secondary)
    .help("New Worktree")
    .padding(.trailing, 4)
  }
}

private struct SidebarFailedRepositoryRow: View {
  let rootURL: URL
  let failureMessage: String
  let store: StoreOf<RepositoriesFeature>

  var body: some View {
    let standardizedRootURL = rootURL.standardizedFileURL
    let name = Repository.name(for: standardizedRootURL)
    let path = standardizedRootURL.path(percentEncoded: false)

    FailedRepositoryRow(
      name: name,
      path: path,
      showFailure: {
        let message = "\(path)\n\n\(failureMessage)"
        store.send(.presentAlert(title: "Unable to load \(name)", message: message))
      },
      removeRepository: {
        store.send(.removeFailedRepository(path))
      }
    )
    .padding(.horizontal, 12)
  }
}
