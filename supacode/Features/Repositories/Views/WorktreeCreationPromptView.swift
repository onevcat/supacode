import ComposableArchitecture
import SwiftUI

struct WorktreeCreationPromptView: View {
  @Bindable var store: StoreOf<WorktreeCreationPromptFeature>
  @FocusState private var isBranchFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("New Worktree")
          .font(.title3)
        Text("Create a branch in \(store.repositoryName)")
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Branch name")
          .foregroundStyle(.secondary)
        TextField("feature/my-change", text: $store.branchName)
          .textFieldStyle(.roundedBorder)
          .focused($isBranchFieldFocused)
          .onSubmit {
            store.send(.createButtonTapped)
          }
      }

      Picker("Branch from", selection: $store.selectedBaseRef) {
        Text(store.automaticBaseRefLabel)
          .tag(Optional<String>.none)
        ForEach(store.baseRefOptions, id: \.self) { ref in
          Text(ref)
            .tag(Optional(ref))
        }
      }

      if let validationMessage = store.validationMessage, !validationMessage.isEmpty {
        Text(validationMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      HStack {
        if store.isValidating {
          ProgressView()
            .controlSize(.small)
        }
        Spacer()
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)
        .help("Cancel (Esc)")
        Button("Create") {
          store.send(.createButtonTapped)
        }
        .keyboardShortcut(.defaultAction)
        .help("Create (↩)")
        .disabled(store.isValidating)
      }
    }
    .padding(20)
    .frame(minWidth: 420)
    .task {
      isBranchFieldFocused = true
    }
  }
}
