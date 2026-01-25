import ComposableArchitecture
import Foundation

struct GithubCLIClient {
  var defaultBranch: @Sendable (URL) async throws -> String
  var latestRun: @Sendable (URL, String) async throws -> GithubWorkflowRun?
  var currentPullRequest: @Sendable (URL) async throws -> GithubPullRequest?
  var isAvailable: @Sendable () async -> Bool
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
        let output = try await runGhAllowingNoPR(
          shell: shell,
          arguments: [
            "pr",
            "view",
            "--json",
            "number,title,state,isDraft,reviewDecision,updatedAt",
          ],
          repoRoot: worktreeRoot
        )
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
      }
    )
  }()

  static let testValue = GithubCLIClient(
    defaultBranch: { _ in "main" },
    latestRun: { _, _ in nil },
    currentPullRequest: { _ in nil },
    isAvailable: { true }
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
