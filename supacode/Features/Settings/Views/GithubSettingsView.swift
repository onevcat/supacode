import ComposableArchitecture
import SwiftUI

@MainActor @Observable
final class GithubSettingsViewModel {
  enum State: Equatable {
    case loading
    case notInstalled
    case notAuthenticated
    case authenticated(username: String)
  }

  var state: State = .loading

  @ObservationIgnored
  @Dependency(\.githubCLI) private var githubCLI

  func load() async {
    state = .loading
    let isAvailable = await githubCLI.isAvailable()
    guard isAvailable else {
      state = .notInstalled
      return
    }

    do {
      let username = try await githubCLI.currentUser()
      state = .authenticated(username: username)
    } catch {
      state = .notAuthenticated
    }
  }
}

struct GithubSettingsView: View {
  @State private var viewModel = GithubSettingsViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section("GitHub CLI") {
          switch viewModel.state {
          case .loading:
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Checking GitHub CLI...")
                .foregroundStyle(.secondary)
            }

          case .notInstalled:
            VStack(alignment: .leading, spacing: 8) {
              Label("GitHub CLI not installed", systemImage: "xmark.circle")
                .foregroundStyle(.red)
              Text("Install gh CLI to enable GitHub integration.")
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

          case .authenticated(let username):
            LabeledContent("Signed in as") {
              Text(username)
                .monospaced()
            }
          }
        }
      }
      .formStyle(.grouped)

      if case .notInstalled = viewModel.state {
        HStack {
          Button("Install via Homebrew") {
            NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
          }
          .help("Open GitHub CLI installation page")
          Spacer()
        }
        .padding(.top)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      await viewModel.load()
    }
  }
}
