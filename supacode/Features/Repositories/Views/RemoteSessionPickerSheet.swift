import ComposableArchitecture
import SwiftUI

struct RemoteSessionPickerSheet: View {
  @Bindable var store: StoreOf<RemoteSessionPickerFeature>
  @FocusState private var isManagedSessionFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Attach tmux Session")
          .font(.title3)
        Text("Choose a tmux session for the selected remote repository.")
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Remote path")
          .foregroundStyle(.secondary)
        Text(store.remotePath)
          .font(.body.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Attach existing session")
          .foregroundStyle(.secondary)
        Picker("Existing sessions", selection: $store.selectedSessionName) {
          ForEach(store.sessions, id: \.self) { sessionName in
            Text(sessionName)
              .tag(sessionName)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Create managed session")
          .foregroundStyle(.secondary)
        TextField("Session name", text: $store.managedSessionName)
          .textFieldStyle(.roundedBorder)
          .focused($isManagedSessionFieldFocused)
      }

      HStack {
        Spacer()
        Button("Cancel") {
          store.send(.cancelTapped)
        }
        .keyboardShortcut(.cancelAction)
        .help("Cancel (Esc)")
        Button("Attach") {
          store.send(.attachTapped)
        }
        .help("Attach selected tmux session")
        .disabled(!store.canAttachSelectedSession)
        Button("Create and Attach") {
          store.send(.createAndAttachTapped)
        }
        .keyboardShortcut(.defaultAction)
        .help("Create (if needed) and attach to this tmux session (Return)")
        .disabled(!store.canCreateManagedSession)
      }
    }
    .padding(20)
    .frame(minWidth: 500, idealWidth: 560)
    .task {
      isManagedSessionFieldFocused = false
    }
  }
}
