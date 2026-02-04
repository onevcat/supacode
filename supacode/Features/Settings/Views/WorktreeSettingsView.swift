import ComposableArchitecture
import SwiftUI

struct WorktreeSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section("Worktree") {
          VStack(alignment: .leading) {
            Toggle(
              "Also delete local branch when deleting a worktree",
              isOn: $store.deleteBranchOnDeleteWorktree
            )
            .help("Delete the local branch when deleting a worktree")
            Text("Removes the local branch along with the worktree. Remote branches must be deleted on GitHub.")
              .foregroundStyle(.secondary)
            Text("Uncommitted changes will be lost.")
              .foregroundStyle(.red)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Toggle(
            "Automatically archive merged worktrees",
            isOn: $store.automaticallyArchiveMergedWorktrees
          )
          .help("Archive worktrees automatically when their pull requests are merged.")
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
