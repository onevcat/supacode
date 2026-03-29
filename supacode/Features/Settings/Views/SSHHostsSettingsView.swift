import ComposableArchitecture
import SwiftUI

struct SSHHostsSettingsView: View {
  @Bindable var store: StoreOf<SSHHostsFeature>

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        List(selection: hostSelection) {
          ForEach(store.hosts) { profile in
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.displayName)
              Text(hostSubtitle(profile))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            }
            .tag(Optional(profile.id))
          }
        }
        .frame(minWidth: 250, maxWidth: 280)

        HStack {
          Button {
            store.send(.addHostTapped)
          } label: {
            Label("Add Host", systemImage: "plus")
          }
          .help("Add a new SSH host profile")

          Button {
            store.send(.deleteHostTapped)
          } label: {
            Label("Delete Host", systemImage: "trash")
          }
          .help("Delete the selected SSH host profile")
          .disabled(store.selectedHostID == nil)
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)

      VStack(alignment: .leading, spacing: 12) {
        if store.isCreating || store.selectedHostID != nil {
          Form {
            Section("Host Details") {
              TextField("Display name", text: $store.displayName)
                .textFieldStyle(.roundedBorder)
              TextField("Host", text: $store.host)
                .textFieldStyle(.roundedBorder)
              TextField("User", text: $store.user)
                .textFieldStyle(.roundedBorder)
              TextField("Port (optional)", text: $store.port)
                .textFieldStyle(.roundedBorder)
              Picker("Authentication", selection: $store.authMethod) {
                Text("Public Key")
                  .tag(SSHHostProfile.AuthMethod.publicKey)
                Text("Password")
                  .tag(SSHHostProfile.AuthMethod.password)
              }
              .pickerStyle(.segmented)
            }
          }
          .formStyle(.grouped)

          if let validationMessage = store.validationMessage, !validationMessage.isEmpty {
            Text(validationMessage)
              .foregroundStyle(.red)
          }

          Button(store.isCreating ? "Create Host" : "Save Changes") {
            store.send(.saveButtonTapped)
          }
          .buttonStyle(.borderedProminent)
          .help(store.isCreating ? "Create this host profile" : "Save changes to this host profile")
        } else {
          Text("Select an SSH host profile or add a new one.")
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .onAppear {
      store.send(.task)
    }
    .alert(store: store.scope(state: \.$alert, action: \.alert))
  }

  private var hostSelection: Binding<SSHHostProfile.ID?> {
    Binding(
      get: { store.selectedHostID },
      set: { store.send(.hostSelected($0)) }
    )
  }

  private func hostSubtitle(_ profile: SSHHostProfile) -> String {
    let hostValue =
      if profile.user.isEmpty {
        profile.host
      } else {
        "\(profile.user)@\(profile.host)"
      }
    if let port = profile.port {
      return "\(hostValue):\(port)"
    }
    return hostValue
  }
}
