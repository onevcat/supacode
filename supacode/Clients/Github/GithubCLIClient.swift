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
  var batchPullRequests: @Sendable (String, String, String, [String]) async throws -> [String: GithubPullRequest]
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
      batchPullRequests: { host, owner, repo, branches in
        let dedupedBranches = deduplicatedBranches(branches)
        guard !dedupedBranches.isEmpty else {
          return [:]
        }
        let chunkSize = 25
        var results: [String: GithubPullRequest] = [:]
        var index = 0
        while index < dedupedBranches.count {
          let end = min(index + chunkSize, dedupedBranches.count)
          let chunk = Array(dedupedBranches[index..<end])
          let (query, aliasMap) = makeBatchPullRequestsQuery(branches: chunk)
          let output = try await runGh(
            shell: shell,
            arguments: [
              "api",
              "graphql",
              "--hostname",
              host,
              "-f",
              "query=\(query)",
              "-f",
              "owner=\(owner)",
              "-f",
              "repo=\(repo)",
            ],
            repoRoot: nil
          )
          if !output.isEmpty {
            let data = Data(output.utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(GithubGraphQLPullRequestResponse.self, from: data)
            let prsByBranch = response.pullRequestsByBranch(
              aliasMap: aliasMap,
              owner: owner,
              repo: repo
            )
            results.merge(prsByBranch) { _, new in new }
          }
          index = end
        }
        return results
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
          let activeAccount = accounts.first(where: { $0.active })
        else {
          return nil
        }
        return GithubAuthStatus(username: activeAccount.login, host: host)
      }
    )
  }()

  static let testValue = GithubCLIClient(
    defaultBranch: { _ in "main" },
    latestRun: { _, _ in nil },
    batchPullRequests: { _, _, _, _ in [:] },
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

nonisolated private func deduplicatedBranches(_ branches: [String]) -> [String] {
  var seen = Set<String>()
  return branches.filter { !$0.isEmpty && seen.insert($0).inserted }
}

nonisolated private func makeBatchPullRequestsQuery(
  branches: [String]
) -> (query: String, aliasMap: [String: String]) {
  var aliasMap: [String: String] = [:]
  var selections: [String] = []
  for (index, branch) in branches.enumerated() {
    let alias = "branch\(index)"
    aliasMap[alias] = branch
    let escapedBranch = escapeGraphQLString(branch)
    let selection = """
      \(alias): pullRequests(first: 5, states: [OPEN, MERGED], headRefName: \"\(escapedBranch)\") {
        nodes {
          number
          title
          state
          additions
          deletions
          isDraft
          reviewDecision
          url
          updatedAt
          headRefName
          headRepository {
            name
            owner { login }
          }
          statusCheckRollup {
            contexts(first: 100) {
              nodes {
                ... on CheckRun {
                  name
                  status
                  conclusion
                  startedAt
                  completedAt
                  detailsUrl
                }
                ... on StatusContext {
                  context
                  state
                  targetUrl
                  createdAt
                }
              }
            }
          }
        }
      }
      """
    selections.append(selection)
  }
  let selectionBlock = selections.joined(separator: "\n")
  let query = """
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
    \(selectionBlock)
      }
    }
    """
  return (query, aliasMap)
}

nonisolated private func escapeGraphQLString(_ value: String) -> String {
  value
    .replacing("\\", with: "\\\\")
    .replacing("\"", with: "\\\"")
    .replacing("\n", with: "\\n")
    .replacing("\r", with: "\\r")
    .replacing("\t", with: "\\t")
}

nonisolated private func runGh(
  shell: ShellClient,
  arguments: [String],
  repoRoot: URL?
) async throws -> String {
  let env = URL(fileURLWithPath: "/usr/bin/env")
  let command = ([env.path(percentEncoded: false)] + ["gh"] + arguments).joined(separator: " ")
  do {
    let shouldLog = !arguments.contains("graphql")
    return try await shell.runLogin(env, ["gh"] + arguments, repoRoot, log: shouldLog).stdout
  } catch {
    if let shellError = error as? ShellClientError {
      let message = shellError.errorDescription ?? "Command failed: \(command)"
      throw GithubCLIError.commandFailed(message)
    }
    throw GithubCLIError.commandFailed(error.localizedDescription)
  }
}

nonisolated private func decodeAuthStatusResponse(from data: Data) throws -> GithubAuthStatusResponse {
  try JSONDecoder().decode(GithubAuthStatusResponse.self, from: data)
}
