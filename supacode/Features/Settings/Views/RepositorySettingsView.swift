import ComposableArchitecture
import SwiftUI

struct RepositorySettingsView: View {
  @Bindable var store: StoreOf<RepositorySettingsFeature>

  var body: some View {
    Form {
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
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      store.send(.task)
    }
  }
}
