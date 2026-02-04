import ComposableArchitecture
import SwiftUI

struct ArchivedWorktreesDetailView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>

  var body: some View {
    let groups = store.state.archivedWorktreesByRepository()
    if groups.isEmpty {
      ContentUnavailableView(
        "Archived Worktrees",
        systemImage: "archivebox",
        description: Text("Archive worktrees to keep them out of the main list.")
      )
    } else {
      List {
        ForEach(groups, id: \.repository.id) { group in
          Section(group.repository.name) {
            ForEach(group.worktrees) { worktree in
              ArchivedWorktreeRowView(
                worktree: worktree,
                info: store.state.worktreeInfo(for: worktree.id),
                onUnarchive: {
                  store.send(.unarchiveWorktree(worktree.id))
                },
                onDelete: {
                  store.send(.requestDeleteWorktree(worktree.id, group.repository.id))
                }
              )
            }
          }
        }
      }
    }
  }
}
