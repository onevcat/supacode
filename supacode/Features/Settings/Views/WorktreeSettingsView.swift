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
          VStack(alignment: .leading) {
            Toggle(
              "Prompt for branch name during creation",
              isOn: $store.promptForWorktreeCreation
            )
            .help("Ask for branch name and base ref before creating a worktree.")
            Text("When enabled, you choose the branch name and where it branches from before creating the worktree.")
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
