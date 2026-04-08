import ComposableArchitecture
import SwiftUI

struct WorktreeSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    let exampleRepositoryRoot = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "code/my-repo", directoryHint: .isDirectory)
    let exampleWorktreePath = SupacodePaths.exampleWorktreePath(
      for: exampleRepositoryRoot,
      globalDefaultPath: store.defaultWorktreeBaseDirectoryPath,
      repositoryOverridePath: nil
    )
    VStack(alignment: .leading) {
      Form {
        Section("Worktree") {
          VStack(alignment: .leading) {
            TextField(
              "Default: current behavior",
              text: $store.defaultWorktreeBaseDirectoryPath
            )
            .textFieldStyle(.roundedBorder)
            Text("Default directory for new worktrees across repositories. Leave empty to keep current behavior.")
              .foregroundStyle(.secondary)
            Text("Example new worktree path: \(exampleWorktreePath)")
              .foregroundStyle(.secondary)
              .monospaced()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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
          Picker(selection: $store.mergedWorktreeAction) {
            Text("Do nothing").tag(MergedWorktreeAction?.none)
            ForEach(MergedWorktreeAction.allCases) { action in
              Text(action.title).tag(MergedWorktreeAction?.some(action))
            }
          } label: {
            Text("When a pull request is merged")
            switch store.mergedWorktreeAction {
            case .archive:
              Text("Archives worktrees when their pull requests are merged.")
            case .delete:
              Text("Follows the \"Delete local branch with worktree\" option below.")
            case nil:
              EmptyView()
            }
          }
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
