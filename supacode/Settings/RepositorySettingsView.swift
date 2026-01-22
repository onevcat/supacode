import SwiftUI

struct RepositorySettingsView: View {
  let repositoryRootURL: URL
  @State private var model: RepositorySettingsModel

  init(repositoryRootURL: URL) {
    self.repositoryRootURL = repositoryRootURL
    _model = State(initialValue: RepositorySettingsModel(rootURL: repositoryRootURL))
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $model.setupScript)
            .font(.body)
            .frame(minHeight: 120)
          if model.setupScript.isEmpty {
            Text("echo 123")
              .foregroundStyle(.secondary)
              .padding(.top, 8)
              .padding(.leading, 6)
              .font(.body)
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
    .scenePadding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
