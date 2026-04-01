import ComposableArchitecture
import Foundation
import SwiftUI

struct SidebarListView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var remoteGroupsStore: StoreOf<RemoteGroupsFeature>
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Binding var sidebarSelections: Set<SidebarSelection>
  let terminalManager: WorktreeTerminalManager
  @State private var isDragActive = false

  var body: some View {
    let state = store.state
    let remoteState = remoteGroupsStore.state
    let hotkeyRows = state.orderedWorktreeRows(includingRepositoryIDs: expandedRepoIDs)
    let orderedRoots = state.orderedRepositoryRoots()
    let selectedWorktreeIDs = Set(sidebarSelections.compactMap(\.worktreeID))
    let selection = Binding<Set<SidebarSelection>>(
      get: {
        if let remoteSelection = sidebarSelection(from: remoteState.selection) {
          return [remoteSelection]
        }
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
        let remoteGroups: [(UUID, String)] = nextSelections.compactMap { selection in
          guard case .remoteGroup(let endpointID, let group) = selection else { return nil }
          return (endpointID, group)
        }
        let remoteEndpoints: [UUID] = nextSelections.compactMap { selection in
          guard case .remoteEndpoint(let endpointID) = selection else { return nil }
          return endpointID
        }
        let repositorySelections: [Repository.ID] = nextSelections.compactMap { selection in
          guard case .repository(let repositoryID) = selection else { return nil }
          return repositoryID
        }

        if let (endpointID, group) = remoteGroups.first {
          sidebarSelections = [.remoteGroup(endpointID: endpointID, group: group)]
          remoteGroupsStore.send(.selectGroup(endpointID: endpointID, group: group))
          return
        }

        if let endpointID = remoteEndpoints.first {
          sidebarSelections = [.remoteEndpoint(endpointID)]
          remoteGroupsStore.send(.selectOverview(endpointID))
          return
        }

        if nextSelections.contains(.canvas) {
          sidebarSelections = [.canvas]
          remoteGroupsStore.send(.clearSelection)
          store.send(.selectCanvas)
          return
        }

        if nextSelections.contains(.archivedWorktrees) {
          sidebarSelections = [.archivedWorktrees]
          remoteGroupsStore.send(.clearSelection)
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
            remoteGroupsStore.send(.clearSelection)
            sidebarSelections = []
          } else {
            sidebarSelections = [.repository(repositoryID)]
            remoteGroupsStore.send(.clearSelection)
            store.send(.selectRepository(repositoryID))
          }
          return
        }

        let worktreeIDs = Set(nextSelections.compactMap(\.worktreeID))
        guard !worktreeIDs.isEmpty else {
          sidebarSelections = []
          remoteGroupsStore.send(.clearSelection)
          store.send(.selectWorktree(nil))
          return
        }
        sidebarSelections = Set(worktreeIDs.map(SidebarSelection.worktree))
        remoteGroupsStore.send(.clearSelection)
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
                store.send(.removeFailedRepository(repositoryID))
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
          store.send(.repositoriesMoved(offsets, destination))
        }
      }
      RemoteGroupsSectionView(store: remoteGroupsStore)
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
      SidebarFooterView(store: store, remoteGroupsStore: remoteGroupsStore)
    }
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

  private func sidebarSelection(from remoteSelection: RemoteSelection) -> SidebarSelection? {
    switch remoteSelection {
    case .none:
      return nil
    case .overview(let endpointID):
      return .remoteEndpoint(endpointID)
    case .group(let endpointID, let group):
      return .remoteGroup(endpointID: endpointID, group: group)
    }
  }
}
