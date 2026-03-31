import ComposableArchitecture
import SwiftUI

struct WorktreeCreationPromptView: View {
  @Bindable var store: StoreOf<WorktreeCreationPromptFeature>
  @FocusState private var isBranchFieldFocused: Bool

  var body: some View {
    Form {
      Section {
        TextField("Branch name", text: $store.branchName)
          .focused($isBranchFieldFocused)
          .onSubmit {
            store.send(.createButtonTapped)
          }
      } header: {
        // `NavigationStack` with title and subtitle is bugged inside
        // sheets in macOS 26.*, and this is a nice enough fallback.
        Text("New Worktree")
        Text("Create a branch in `\(store.repositoryName)`.")
      }
      .headerProminence(.increased)

      Section {
        Picker(selection: $store.selectedBaseRef) {
          automaticRefLabel
            .tag(Optional<String>.none)
          ForEach(store.baseRefOptions, id: \.self) { ref in
            Text(ref)
              .tag(Optional(ref))
          }
        } label: {
          Text("Base ref")
          Text("The branch or ref the new worktree will be created from.")
        }

        Toggle(isOn: $store.fetchOrigin) {
          Text("Fetch remote branch")
          Text(
            "Runs `git fetch` to ensure the base branch is up to date before creating the worktree."
          )
        }
      } footer: {
        if let validationMessage = store.validationMessage, !validationMessage.isEmpty {
          Text(validationMessage)
            .foregroundStyle(.red)
        }
      }

    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom, spacing: 0) {
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
      .padding(.horizontal, 20)
      .padding(.bottom, 20)
    }
    .frame(minWidth: 420)
    .task { isBranchFieldFocused = true }
  }

  private var automaticRefLabel: Text {
    let ref = store.automaticBaseRef
    guard !ref.isEmpty else { return Text("Auto") }
    return Text("Auto \(Text(ref).foregroundStyle(.secondary))")
  }
}
