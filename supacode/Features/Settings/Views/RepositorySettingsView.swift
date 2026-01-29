import ComposableArchitecture
import SwiftUI

struct RepositorySettingsView: View {
  @Bindable var store: StoreOf<RepositorySettingsFeature>

  var body: some View {
    Form {
      Section {
        Toggle(
          "Copy ignored files to new worktrees",
          isOn: Binding(
            get: { store.settings.copyIgnoredOnWorktreeCreate },
            set: { store.send(.setCopyIgnoredOnWorktreeCreate($0)) }
          )
        )
        Toggle(
          "Copy untracked files to new worktrees",
          isOn: Binding(
            get: { store.settings.copyUntrackedOnWorktreeCreate },
            set: { store.send(.setCopyUntrackedOnWorktreeCreate($0)) }
          )
        )
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
            Text("echo 123")
              .foregroundStyle(.secondary)
              .padding(.top, 8)
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
            Text("echo \"Run script\"")
              .foregroundStyle(.secondary)
              .padding(.top, 8)
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
