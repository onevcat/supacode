import ComposableArchitecture
import SwiftUI

@MainActor @Observable
final class GithubSettingsViewModel {
  enum State: Equatable {
    case loading
    case unavailable
    case notAuthenticated
    case authenticated(username: String, host: String)
    case error(String)
  }

  var state: State = .loading

  @ObservationIgnored
  @Dependency(\.githubIntegration) private var githubIntegration

  @ObservationIgnored
  @Dependency(\.githubCLI) private var githubCLI

  func load() async {
    state = .loading
    let isAvailable = await githubIntegration.isAvailable()
    guard isAvailable else {
      state = .unavailable
      return
    }

    do {
      if let status = try await githubCLI.authStatus() {
        state = .authenticated(username: status.username, host: status.host)
      } else {
        state = .notAuthenticated
      }
    } catch {
      state = .error(error.localizedDescription)
    }
  }
}

struct GithubSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var viewModel = GithubSettingsViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section("GitHub integration") {
          Toggle(
            "Enable GitHub integration",
            isOn: Binding(
              get: { store.githubIntegrationEnabled },
              set: { store.send(.setGithubIntegrationEnabled($0)) }
            )
          )
          .help("Enable GitHub integration")
        }
        Section("GitHub CLI") {
          switch viewModel.state {
          case .loading:
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Checking GitHub CLI...")
                .foregroundStyle(.secondary)
            }

          case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
              Label("GitHub integration unavailable", systemImage: "xmark.circle")
                .foregroundStyle(.red)
              Text("Enable GitHub integration and install gh CLI to use pull request checks.")
                .foregroundStyle(.secondary)
                .font(.callout)
            }

          case .notAuthenticated:
            VStack(alignment: .leading, spacing: 8) {
              Label("Not authenticated", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
              Text("Run `gh auth login` in terminal to authenticate.")
                .foregroundStyle(.secondary)
                .font(.callout)
            }

          case .authenticated(let username, let host):
            LabeledContent("Signed in as") {
              Text(username)
                .ghosttyMonospaced(.body)
            }
            LabeledContent("Host") {
              Text(host)
                .ghosttyMonospaced(.body)
            }

          case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
              Label("Error checking status", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
              Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
          }
        }
      }
      .formStyle(.grouped)

      if case .unavailable = viewModel.state {
        HStack {
          Button("Get GitHub CLI") {
            NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
          }
          .help("Open GitHub CLI website")
          Spacer()
        }
        .padding(.top)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      await viewModel.load()
    }
    .onChange(of: store.githubIntegrationEnabled) { _, _ in
      Task {
        await viewModel.load()
      }
    }
  }
}
