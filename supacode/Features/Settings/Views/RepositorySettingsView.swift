import ComposableArchitecture
import SwiftUI

struct RepositorySettingsView: View {
  @Bindable var store: StoreOf<RepositorySettingsFeature>

  var body: some View {
    let baseRefOptions =
      store.branchOptions.isEmpty ? [store.defaultWorktreeBaseRef] : store.branchOptions
    Form {
      Section {
        if store.isBranchDataLoaded {
          Picker(
            "Branch new workspaces from",
            selection: Binding(
              get: {
                (store.settings.worktreeBaseRef ?? "").isEmpty
                  ? store.defaultWorktreeBaseRef
                  : store.settings.worktreeBaseRef ?? store.defaultWorktreeBaseRef
              },
              set: { store.send(.setWorktreeBaseRef($0)) }
            )
          ) {
            ForEach(baseRefOptions, id: \.self) { ref in
              Text(ref)
                .tag(ref)
            }
          }
          .labelsHidden()
        } else {
          ProgressView()
            .controlSize(.small)
        }
      } header: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Branch new workspaces from")
          Text("Each workspace is an isolated copy of your codebase.")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Toggle(
          "Copy ignored files to new worktrees",
          isOn: Binding(
            get: { store.settings.copyIgnoredOnWorktreeCreate },
            set: { store.send(.setCopyIgnoredOnWorktreeCreate($0)) }
          )
        )
        .disabled(store.isBareRepository)
        Toggle(
          "Copy untracked files to new worktrees",
          isOn: Binding(
            get: { store.settings.copyUntrackedOnWorktreeCreate },
            set: { store.send(.setCopyUntrackedOnWorktreeCreate($0)) }
          )
        )
        .disabled(store.isBareRepository)
        if store.isBareRepository {
          Text("Copy flags are ignored for bare repositories.")
            .foregroundStyle(.secondary)
        }
      } header: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Worktree")
          Text("Applies when creating a new worktree")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        ZStack(alignment: .topLeading) {
          TextEditor(
            text: Binding(
              get: { store.settings.setupScript },
              set: { store.send(.setSetupScript($0)) }
            )
          )
          .font(.body)
          .monospaced()
          .frame(minHeight: 120)
          if store.settings.setupScript.isEmpty {
            Text("claude --dangerously-skip-permissions")
              .foregroundStyle(.secondary)
              .padding(.leading, 6)
              .font(.body)
              .monospaced()
              .allowsHitTesting(false)
          }
        }
      } header: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Setup Script")
          Text("Initial setup script that will be launched once after worktree creation")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        ZStack(alignment: .topLeading) {
          TextEditor(
            text: Binding(
              get: { store.settings.runScript },
              set: { store.send(.setRunScript($0)) }
            )
          )
          .font(.body)
          .monospaced()
          .frame(minHeight: 120)
          if store.settings.runScript.isEmpty {
            Text("npm run dev")
              .foregroundStyle(.secondary)
              .padding(.leading, 6)
              .font(.body)
              .monospaced()
              .allowsHitTesting(false)
          }
        }
      } header: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Run Script")
          Text("Run script launched on demand from the toolbar")
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      store.send(.task)
    }
  }
}
