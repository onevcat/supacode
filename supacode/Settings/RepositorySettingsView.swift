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
        TextField("Start up command", text: $model.startupCommand, prompt: Text("echo 123"))
      }
    }
    .formStyle(.grouped)
    .scenePadding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
