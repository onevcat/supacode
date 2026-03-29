import ComposableArchitecture
import SwiftUI

struct RemoteConnectSheet: View {
  @Bindable var store: StoreOf<RemoteConnectFeature>
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case displayName
    case host
    case user
    case port
    case password
    case remotePath
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Connect Remote Repository")
          .font(.title3)
        Text(
          store.step == .host
            ? "Choose a host profile or enter SSH details first."
            : "Pick the remote repository folder on \(store.resolvedDisplayName)."
        )
        .foregroundStyle(.secondary)
      }

      stepIndicator

      if store.step == .host {
        hostStep
      } else {
        repositoryStep
      }

      if let validationMessage = store.validationMessage, !validationMessage.isEmpty {
        Text(validationMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      HStack {
        if store.isSubmitting {
          ProgressView()
            .controlSize(.small)
        }
        Spacer()
        if store.step == .repository {
          Button("Back") {
            store.send(.backButtonTapped)
          }
          .help("Go back to host details")
        }
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)
        .help("Cancel (Esc)")
        Button(store.step == .host ? "Continue" : "Connect") {
          store.send(store.step == .host ? .continueButtonTapped : .connectButtonTapped)
        }
        .keyboardShortcut(.defaultAction)
        .help(store.step == .host ? "Continue (Return)" : "Connect (Return)")
        .disabled(store.isSubmitting)
      }
    }
    .padding(20)
    .frame(minWidth: 560, idealWidth: 620)
    .task(id: store.step) {
      focusedField =
        if store.step == .host {
          store.authMethod == .password ? .password : .host
        } else {
          .remotePath
        }
    }
  }

  private var stepIndicator: some View {
    HStack(spacing: 12) {
      stepBadge(number: 1, title: "Host", isActive: store.step == .host)
      Image(systemName: "chevron.right")
        .foregroundStyle(.secondary)
        .font(.footnote.weight(.semibold))
      stepBadge(number: 2, title: "Repository", isActive: store.step == .repository)
    }
  }

  private func stepBadge(number: Int, title: String, isActive: Bool) -> some View {
    HStack(spacing: 8) {
      Text("\(number)")
        .font(.callout.monospaced())
        .frame(width: 24, height: 24)
        .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
        .foregroundStyle(isActive ? .white : .primary)
        .clipShape(Circle())
      Text(title)
        .fontWeight(isActive ? .semibold : .regular)
    }
  }

  private var hostStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !store.savedHostProfiles.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Saved hosts")
            .foregroundStyle(.secondary)
          Picker("Saved hosts", selection: savedHostSelection) {
            Text("New host")
              .tag(Optional<SSHHostProfile.ID>.none)
            ForEach(store.savedHostProfiles) { profile in
              Text(hostLabel(profile))
                .tag(Optional(profile.id))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          labeledField(
            title: "Name",
            prompt: "Build Box",
            text: $store.displayName,
            field: .displayName
          )
          labeledField(
            title: "Host",
            prompt: "example.com",
            text: $store.host,
            field: .host
          )
        }
        GridRow {
          labeledField(
            title: "User",
            prompt: "deploy",
            text: $store.user,
            field: .user
          )
          labeledField(
            title: "Port",
            prompt: "22",
            text: $store.port,
            field: .port
          )
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Authentication")
          .foregroundStyle(.secondary)
        Picker("Authentication", selection: $store.authMethod) {
          ForEach(SSHHostProfile.AuthMethod.allCases, id: \.self) { method in
            Text(authenticationTitle(method))
              .tag(method)
          }
        }
        .pickerStyle(.segmented)
      }

      if store.authMethod == .password {
        labeledSecureField(
          title: "Password",
          prompt: "Enter SSH password",
          text: $store.password,
          field: .password
        )
      }
    }
  }

  private var repositoryStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Host")
          .foregroundStyle(.secondary)
        Text(hostSummary)
          .monospaced()
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Remote path")
          .foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 10) {
          TextField("~/src/repo", text: $store.remotePath)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .remotePath)
            .onSubmit {
              guard !store.isSubmitting else {
                return
              }
              store.send(.connectButtonTapped)
            }
          Button("Browse Remote Folders") {
            store.send(.browseRemoteFoldersButtonTapped)
          }
          .help("Browse folders over SSH and pick a repository directory")
        }
        Text("Use an absolute path or start with `~/`. Browsing resolves the final path for you.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .monospaced()
      }

      if let directoryBrowser = store.directoryBrowser {
        directoryBrowserView(directoryBrowser)
      }
    }
  }

  private func directoryBrowserView(
    _ directoryBrowser: RemoteConnectFeature.DirectoryBrowserState
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Remote folders")
          .font(.headline)
        Spacer()
        Button {
          store.send(.directoryBrowserUpButtonTapped)
        } label: {
          Label("Up", systemImage: "arrow.up")
        }
        .help("Go to the parent folder")
        .disabled(directoryBrowser.currentPath == "/")
        Button("Use Current Folder") {
          store.send(.directoryBrowserChooseCurrentFolderButtonTapped)
        }
        .help("Use \(directoryBrowser.currentPath) as the repository path")
        Button("Close") {
          store.send(.directoryBrowserDismissed)
        }
        .help("Close the remote folder browser")
      }

      Text(directoryBrowser.currentPath)
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)

      if directoryBrowser.isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading folders…")
            .foregroundStyle(.secondary)
        }
      } else if let errorMessage = directoryBrowser.errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      } else if directoryBrowser.childDirectories.isEmpty {
        Text("No child folders found.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(directoryBrowser.childDirectories, id: \.self) { path in
              Button {
                store.send(.directoryBrowserEntryTapped(path))
              } label: {
                HStack {
                  Image(systemName: "folder")
                  Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospaced()
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
              }
              .buttonStyle(.plain)
              .help("Browse \(path)")
            }
          }
        }
        .frame(minHeight: 160, maxHeight: 220)
      }
    }
    .padding(14)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func labeledField(
    title: String,
    prompt: String,
    text: Binding<String>,
    field: Field
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .foregroundStyle(.secondary)
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: field)
    }
  }

  private func labeledSecureField(
    title: String,
    prompt: String,
    text: Binding<String>,
    field: Field
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .foregroundStyle(.secondary)
      SecureField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: field)
    }
  }

  private var savedHostSelection: Binding<SSHHostProfile.ID?> {
    Binding(
      get: { store.selectedHostProfileID },
      set: { store.send(.savedHostProfileSelected($0)) }
    )
  }

  private func hostLabel(_ profile: SSHHostProfile) -> String {
    let userAndHost =
      if profile.user.isEmpty {
        profile.host
      } else {
        "\(profile.user)@\(profile.host)"
      }
    return "\(profile.displayName) (\(userAndHost))"
  }

  private func authenticationTitle(_ method: SSHHostProfile.AuthMethod) -> String {
    switch method {
    case .publicKey:
      "Public Key"
    case .password:
      "Password"
    }
  }

  private var hostSummary: String {
    let userAndHost =
      if store.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        store.host
      } else {
        "\(store.user)@\(store.host)"
      }
    if let port = Int(store.port.trimmingCharacters(in: .whitespacesAndNewlines)) {
      return "\(userAndHost):\(port)"
    }
    return userAndHost
  }
}
