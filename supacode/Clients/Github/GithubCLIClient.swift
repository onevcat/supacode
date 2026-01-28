import ComposableArchitecture
import Foundation

struct GithubAuthStatus: Equatable, Sendable {
  let username: String
  let host: String
}

private struct GithubAuthStatusResponse: Sendable {
  let hosts: [String: [GithubAuthAccount]]

  struct GithubAuthAccount: Sendable {
    let active: Bool
    let login: String
  }
}

extension GithubAuthStatusResponse: Decodable {
  private enum CodingKeys: String, CodingKey {
    case hosts
  }

  nonisolated init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.hosts = try container.decode([String: [GithubAuthAccount]].self, forKey: .hosts)
  }
}

extension GithubAuthStatusResponse.GithubAuthAccount: Decodable {
  private enum CodingKeys: String, CodingKey {
    case active
    case login
  }

  nonisolated init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.active = try container.decode(Bool.self, forKey: .active)
    self.login = try container.decode(String.self, forKey: .login)
  }
}

struct GithubCLIClient {
  var defaultBranch: @Sendable (URL) async throws -> String
  var latestRun: @Sendable (URL, String) async throws -> GithubWorkflowRun?
  var currentPullRequest: @Sendable (URL) async throws -> GithubPullRequest?
  var isAvailable: @Sendable () async -> Bool
  var authStatus: @Sendable () async throws -> GithubAuthStatus?
}

extension GithubCLIClient: DependencyKey {
  static let liveValue = {
    let shell = ShellClient.liveValue
    return GithubCLIClient(
      defaultBranch: { repoRoot in
        let output = try await runGh(
          shell: shell,
          arguments: ["repo", "view", "--json", "defaultBranchRef"],
          repoRoot: repoRoot
        )
      let data = Data(output.utf8)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let response = try decoder.decode(GithubRepoViewResponse.self, from: data)
      return response.defaultBranchRef.name
      },
      latestRun: { repoRoot, branch in
        let output = try await runGh(
          shell: shell,
          arguments: [
            "run",
            "list",
            "--branch",
            branch,
            "--limit",
            "1",
            "--json",
            "workflowName,name,displayTitle,status,conclusion,createdAt,updatedAt",
          ],
          repoRoot: repoRoot
        )
      if output.isEmpty {
        return nil
      }
      let data = Data(output.utf8)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let runs = try decoder.decode([GithubWorkflowRun].self, from: data)
      return runs.first
      },
      currentPullRequest: { worktreeRoot in
        let baseFields = [
          "number",
          "title",
          "state",
          "additions",
          "deletions",
          "isDraft",
          "reviewDecision",
          "updatedAt",
          "url",
        ]
        let headRefNameField = "headRefName"
        let statusCheckField = "statusCheckRollup"
        var requestedFields = baseFields + [headRefNameField, statusCheckField]
        var output: String?
        while true {
          do {
            output = try await runGhAllowingNoPR(
              shell: shell,
              arguments: [
                "pr",
                "view",
                "--json",
                requestedFields.joined(separator: ","),
              ],
              repoRoot: worktreeRoot
            )
            break
          } catch {
            let dropHeadRefName = isUnsupportedFieldError(error, fieldName: headRefNameField)
            let dropStatusCheck = isUnsupportedFieldError(error, fieldName: statusCheckField)
            var updatedFields = requestedFields
            if dropHeadRefName {
              updatedFields.removeAll { $0 == headRefNameField }
            }
            if dropStatusCheck {
              updatedFields.removeAll { $0 == statusCheckField }
            }
            if updatedFields == requestedFields {
              throw error
            }
            requestedFields = updatedFields
          }
        }
        guard let output, !output.isEmpty else {
          return nil
        }
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GithubPullRequest.self, from: data)
      },
      isAvailable: {
        do {
          _ = try await runGh(shell: shell, arguments: ["--version"], repoRoot: nil)
          return true
        } catch {
          return false
        }
      },
      authStatus: {
        let output = try await runGh(
          shell: shell,
          arguments: ["auth", "status", "--json", "hosts"],
          repoRoot: nil
        )
        let data = Data(output.utf8)
        let response = try decodeAuthStatusResponse(from: data)
        guard let (host, accounts) = response.hosts.first,
              let activeAccount = accounts.first(where: { $0.active }) else {
          return nil
        }
        return GithubAuthStatus(username: activeAccount.login, host: host)
      }
    )
  }()

  static let testValue = GithubCLIClient(
    defaultBranch: { _ in "main" },
    latestRun: { _, _ in nil },
    currentPullRequest: { _ in nil },
    isAvailable: { true },
    authStatus: { GithubAuthStatus(username: "testuser", host: "github.com") }
  )
}

extension DependencyValues {
  var githubCLI: GithubCLIClient {
    get { self[GithubCLIClient.self] }
    set { self[GithubCLIClient.self] = newValue }
  }
}

nonisolated private func runGh(
  shell: ShellClient,
  arguments: [String],
  repoRoot: URL?
) async throws -> String {
  let env = URL(fileURLWithPath: "/usr/bin/env")
  let command = ([env.path(percentEncoded: false)] + ["gh"] + arguments).joined(separator: " ")
  do {
    return try await shell.runLogin(env, ["gh"] + arguments, repoRoot).stdout
  } catch {
    if let shellError = error as? ShellClientError {
      let message = shellError.errorDescription ?? "Command failed: \(command)"
      throw GithubCLIError.commandFailed(message)
    }
    throw GithubCLIError.commandFailed(error.localizedDescription)
  }
}

nonisolated private func runGhAllowingNoPR(
  shell: ShellClient,
  arguments: [String],
  repoRoot: URL?
) async throws -> String? {
  do {
    return try await runGh(shell: shell, arguments: arguments, repoRoot: repoRoot)
  } catch {
    let message = error.localizedDescription.lowercased()
    if message.contains("no pull requests found") {
      return nil
    }
    throw error
  }
}

nonisolated private func isUnsupportedFieldError(_ error: Error, fieldName: String) -> Bool {
  let message = error.localizedDescription.lowercased()
  let normalizedFieldName = fieldName.lowercased()
  if !message.contains(normalizedFieldName) {
    return false
  }
  return message.contains("unknown") || message.contains("unsupported") || message.contains("field")
}

nonisolated private func decodeAuthStatusResponse(from data: Data) throws -> GithubAuthStatusResponse {
  try JSONDecoder().decode(GithubAuthStatusResponse.self, from: data)
}
