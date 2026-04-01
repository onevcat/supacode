import ComposableArchitecture
import SwiftUI

struct RemoteGroupAddPromptView: View {
  @Bindable var store: StoreOf<RemoteGroupsFeature>
  @FocusState private var isURLFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Add Remote Endpoint")
          .font(.title3)
        Text("Connect a mini-terminal URL and auto-discover groups.")
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Remote URL")
          .foregroundStyle(.secondary)
        TextField(
          "https://example.com/mini-terminal/",
          text: Binding(
            get: { store.addURLDraft },
            set: { store.send(.addURLDraftChanged($0)) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .focused($isURLFieldFocused)
        .onSubmit {
          submit()
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Initial Group (optional)")
          .foregroundStyle(.secondary)
        TextField(
          "leave empty to open overview",
          text: Binding(
            get: { store.addGroupDraft },
            set: { store.send(.addGroupDraftChanged($0)) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          submit()
        }
      }

      HStack {
        Spacer()
        Button("Cancel") {
          store.send(.setAddPromptPresented(false))
        }
        .keyboardShortcut(.cancelAction)
        .help("Cancel (Esc)")

        Button("Connect") {
          submit()
        }
        .keyboardShortcut(.defaultAction)
        .help("Connect (↩)")
        .disabled(!canSubmit)
      }
    }
    .padding(20)
    .frame(minWidth: 520)
    .task {
      isURLFieldFocused = true
    }
  }

  private var canSubmit: Bool {
    let trimmed = store.addURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      url.scheme != nil,
      url.host != nil
    else {
      return false
    }
    return true
  }

  private func submit() {
    guard canSubmit else {
      return
    }
    store.send(
      .submitEndpoint(
        urlText: store.addURLDraft,
        initialGroup: store.addGroupDraft
      )
    )
  }
}
