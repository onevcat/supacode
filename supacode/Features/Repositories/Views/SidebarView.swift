import ComposableArchitecture
import Sharing
import SwiftUI

struct SidebarView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Shared(.appStorage("sidebarCollapsedRepositoryIDs")) private var collapsedRepositoryIDs: [Repository.ID] = []
  @State private var sidebarSelections: Set<SidebarSelection> = []

  var body: some View {
    let state = store.state
    let repositoryIDs = Set(state.repositories.map(\.id))
    let pendingRepositoryIDs = Set(state.pendingWorktrees.map(\.repositoryID))
    let collapsedSet = Set(collapsedRepositoryIDs).intersection(repositoryIDs)
    let expandedRepoIDs = repositoryIDs.subtracting(collapsedSet).union(pendingRepositoryIDs)
    let expandedRepoIDsBinding = Binding<Set<Repository.ID>>(
      get: {
        expandedRepoIDs
      },
      set: { newValue in
        let collapsed = repositoryIDs.subtracting(newValue)
        $collapsedRepositoryIDs.withLock {
          $0 = Array(collapsed).sorted()
        }
      }
    )
    let visibleHotkeyRows = state.orderedWorktreeRows(includingRepositoryIDs: expandedRepoIDs)
    let selectedRow = state.selectedRow(for: state.selectedWorktreeID)
    let selectedWorktreeIDs = Set(sidebarSelections.compactMap(\.worktreeID))
    let selectedRows = visibleHotkeyRows.filter { selectedWorktreeIDs.contains($0.id) }
    let effectiveSelectedRows = selectedRows.isEmpty ? (selectedRow.map { [$0] } ?? []) : selectedRows
    let confirmWorktreeAction: (() -> Void)? = {
      guard let alert = state.confirmWorktreeAlert else { return nil }
      return {
        store.send(.alert(.presented(alert)))
      }
    }()
    let archiveWorktreeAction: (() -> Void)? = {
      let targets =
        effectiveSelectedRows
        .filter { $0.isRemovable && !$0.isMainWorktree && !$0.isDeleting }
        .map {
          RepositoriesFeature.ArchiveWorktreeTarget(
            worktreeID: $0.id,
            repositoryID: $0.repositoryID
          )
        }
      guard !targets.isEmpty else { return nil }
      return {
        if targets.count == 1, let target = targets.first {
          store.send(.requestArchiveWorktree(target.worktreeID, target.repositoryID))
        } else {
          store.send(.requestArchiveWorktrees(targets))
        }
      }
    }()
    let deleteWorktreeAction: (() -> Void)? = {
      let targets =
        effectiveSelectedRows
        .filter { $0.isRemovable && !$0.isDeleting }
        .map {
          RepositoriesFeature.DeleteWorktreeTarget(
            worktreeID: $0.id,
            repositoryID: $0.repositoryID
          )
        }
      guard !targets.isEmpty else { return nil }
      return {
        if targets.count == 1, let target = targets.first {
          store.send(.requestDeleteWorktree(target.worktreeID, target.repositoryID))
        } else {
          store.send(.requestDeleteWorktrees(targets))
        }
      }
    }()
    SidebarListView(
      store: store,
      expandedRepoIDs: expandedRepoIDsBinding,
      sidebarSelections: $sidebarSelections,
      terminalManager: terminalManager
    )
    .focusedSceneValue(\.confirmWorktreeAction, confirmWorktreeAction)
    .focusedSceneValue(\.archiveWorktreeAction, archiveWorktreeAction)
    .focusedSceneValue(\.deleteWorktreeAction, deleteWorktreeAction)
    .focusedSceneValue(\.visibleHotkeyWorktreeRows, visibleHotkeyRows)
      .onAppear {
        sidebarSelections = normalizedSidebarSelections(
          current: sidebarSelections,
          state: state,
          visibleWorktreeIDs: Set(visibleHotkeyRows.map(\.id))
        )
        store.send(.setSidebarSelectedWorktreeIDs(selectedWorktreeIDs(from: sidebarSelections)))
      }
      .onChange(of: state.selection) { _, _ in
        sidebarSelections = normalizedSidebarSelections(
          current: sidebarSelections,
          state: state,
        visibleWorktreeIDs: Set(visibleHotkeyRows.map(\.id))
      )
    }
      .onChange(of: visibleHotkeyRows.map(\.id)) { _, _ in
        sidebarSelections = normalizedSidebarSelections(
          current: sidebarSelections,
          state: state,
          visibleWorktreeIDs: Set(visibleHotkeyRows.map(\.id))
        )
      }
      .onChange(of: sidebarSelections) { _, newValue in
        store.send(.setSidebarSelectedWorktreeIDs(selectedWorktreeIDs(from: newValue)))
      }
      .onChange(of: repositoryIDs) { _, newValue in
        let collapsed = Set(collapsedRepositoryIDs).intersection(newValue)
        $collapsedRepositoryIDs.withLock {
          $0 = Array(collapsed).sorted()
        }
    }
  }

  private func normalizedSidebarSelections(
    current: Set<SidebarSelection>,
    state: RepositoriesFeature.State,
    visibleWorktreeIDs: Set<Worktree.ID>
  ) -> Set<SidebarSelection> {
    if state.isShowingArchivedWorktrees {
      return [.archivedWorktrees]
    }
    var normalized = Set(
      current.compactMap { selection -> SidebarSelection? in
        guard let worktreeID = selection.worktreeID,
          visibleWorktreeIDs.contains(worktreeID)
        else {
          return nil
        }
        return .worktree(worktreeID)
      }
    )
    if let selectedWorktreeID = state.selectedWorktreeID {
      normalized.insert(.worktree(selectedWorktreeID))
    }
    return normalized
  }

  private func selectedWorktreeIDs(from selections: Set<SidebarSelection>) -> Set<Worktree.ID> {
    Set(selections.compactMap(\.worktreeID))
  }
}
