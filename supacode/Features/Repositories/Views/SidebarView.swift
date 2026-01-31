import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @State private var expandedRepoIDs: Set<Repository.ID>

  init(store: StoreOf<RepositoriesFeature>, terminalManager: WorktreeTerminalManager) {
    self.store = store
    self.terminalManager = terminalManager
    let repositoryIDs = Set(store.repositories.map(\.id))
    let pendingRepositoryIDs = Set(store.pendingWorktrees.map(\.repositoryID))
    _expandedRepoIDs = State(initialValue: repositoryIDs.union(pendingRepositoryIDs))
  }

  var body: some View {
    let state = store.state
    let selectedRow = state.selectedRow(for: state.selectedWorktreeID)
    let confirmRemoveWorktreeAction: (() -> Void)? = {
      guard let ids = state.confirmRemoveWorktreeIDs else { return nil }
      return {
        store.send(.alert(.presented(.confirmRemoveWorktree(ids.worktreeID, ids.repositoryID))))
      }
    }()
    let removeWorktreeAction: (() -> Void)? = {
      guard let selectedRow, selectedRow.isRemovable, !selectedRow.isMainWorktree else { return nil }
      return {
        store.send(.requestRemoveWorktree(selectedRow.id, selectedRow.repositoryID))
      }
    }()
    SidebarListView(store: store, expandedRepoIDs: $expandedRepoIDs, terminalManager: terminalManager)
      .focusedSceneValue(\.confirmRemoveWorktreeAction, confirmRemoveWorktreeAction)
      .focusedSceneValue(\.removeWorktreeAction, removeWorktreeAction)
  }
}
