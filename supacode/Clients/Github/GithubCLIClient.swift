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
  var mergePullRequest: @Sendable (URL, Int, PullRequestMergeStrategy) async throws -> Void
  var markPullRequestReady: @Sendable (URL, Int) async throws -> Void
  var rerunFailedJobs: @Sendable (URL, Int) async throws -> Void
  var failedRunLogs: @Sendable (URL, Int) async throws -> String
  var runLogs: @Sendable (URL, Int) async throws -> String
  var isAvailable: @Sendable () async -> Bool
  var authStatus: @Sendable () async throws -> GithubAuthStatus?
}

extension GithubCLIClient: DependencyKey {
  static let liveValue = live()

  static func live(shell: ShellClient = .liveValue) -> GithubCLIClient {
    GithubCLIClient(
      defaultBranch: defaultBranchFetcher(shell: shell),
      latestRun: latestRunFetcher(shell: shell),
      batchPullRequests: batchPullRequestsFetcher(shell: shell),
      mergePullRequest: mergePullRequestFetcher(shell: shell),
      markPullRequestReady: markPullRequestReadyFetcher(shell: shell),
      rerunFailedJobs: rerunFailedJobsFetcher(shell: shell),
      failedRunLogs: failedRunLogsFetcher(shell: shell),
      runLogs: runLogsFetcher(shell: shell),
      isAvailable: isAvailableFetcher(shell: shell),
      authStatus: authStatusFetcher(shell: shell)
    )
  }

  static let testValue = GithubCLIClient(
    defaultBranch: { _ in "main" },
    latestRun: { _, _ in nil },
    batchPullRequests: { _, _, _, _ in [:] },
    mergePullRequest: { _, _, _ in },
    markPullRequestReady: { _, _ in },
    rerunFailedJobs: { _, _ in },
    failedRunLogs: { _, _ in "" },
    runLogs: { _, _ in "" },
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

private struct GithubPullRequestsRequest: Sendable {
  let host: String
  let owner: String
  let repo: String
}

nonisolated private func defaultBranchFetcher(
  shell: ShellClient
) -> @Sendable (URL) async throws -> String {
  { repoRoot in
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
  }
}

nonisolated private func latestRunFetcher(
  shell: ShellClient
) -> @Sendable (URL, String) async throws -> GithubWorkflowRun? {
  { repoRoot, branch in
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
        "databaseId,workflowName,name,displayTitle,status,conclusion,createdAt,updatedAt",
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
  }
}

nonisolated private func batchPullRequestsFetcher(
  shell: ShellClient
) -> @Sendable (String, String, String, [String]) async throws -> [String: GithubPullRequest] {
  { host, owner, repo, branches in
    let dedupedBranches = deduplicatedBranches(branches)
    guard !dedupedBranches.isEmpty else {
      return [:]
    }
    let request = GithubPullRequestsRequest(host: host, owner: owner, repo: repo)
    let chunks = makeBranchChunks(
      dedupedBranches,
      chunkSize: batchPullRequestsChunkSize
    )
    let chunkResults = try await loadPullRequestChunks(
      shell: shell,
      request: request,
      chunks: chunks
    )
    return mergePullRequestChunkResults(
      chunkResults,
      chunkCount: chunks.count
    )
  }
}

nonisolated private func mergePullRequestFetcher(
  shell: ShellClient
) -> @Sendable (URL, Int, PullRequestMergeStrategy) async throws -> Void {
  { repoRoot, pullRequestNumber, strategy in
    _ = try await runGh(
      shell: shell,
      arguments: [
        "pr",
        "merge",
        "\(pullRequestNumber)",
        "--\(strategy.ghArgument)",
      ],
      repoRoot: repoRoot
    )
  }
}

nonisolated private func markPullRequestReadyFetcher(
  shell: ShellClient
) -> @Sendable (URL, Int) async throws -> Void {
  { repoRoot, pullRequestNumber in
    _ = try await runGh(
      shell: shell,
      arguments: [
        "pr",
        "ready",
        "\(pullRequestNumber)",
      ],
      repoRoot: repoRoot
    )
  }
}

nonisolated private func rerunFailedJobsFetcher(
  shell: ShellClient
) -> @Sendable (URL, Int) async throws -> Void {
  { repoRoot, runID in
    _ = try await runGh(
      shell: shell,
      arguments: [
        "run",
        "rerun",
        "\(runID)",
        "--failed",
      ],
      repoRoot: repoRoot
    )
  }
}

nonisolated private func failedRunLogsFetcher(
  shell: ShellClient
) -> @Sendable (URL, Int) async throws -> String {
  { repoRoot, runID in
    try await runGh(
      shell: shell,
      arguments: [
        "run",
        "view",
        "\(runID)",
        "--log-failed",
      ],
      repoRoot: repoRoot
    )
  }
}

nonisolated private func runLogsFetcher(
  shell: ShellClient
) -> @Sendable (URL, Int) async throws -> String {
  { repoRoot, runID in
    try await runGh(
      shell: shell,
      arguments: [
        "run",
        "view",
        "\(runID)",
        "--log",
      ],
      repoRoot: repoRoot
    )
  }
}

nonisolated private func isAvailableFetcher(
  shell: ShellClient
) -> @Sendable () async -> Bool {
  {
    do {
      _ = try await runGh(shell: shell, arguments: ["--version"], repoRoot: nil)
      return true
    } catch {
      return false
    }
  }
}

nonisolated private func authStatusFetcher(
  shell: ShellClient
) -> @Sendable () async throws -> GithubAuthStatus? {
  {
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
}

nonisolated private func deduplicatedBranches(_ branches: [String]) -> [String] {
  var seen = Set<String>()
  return branches.filter { !$0.isEmpty && seen.insert($0).inserted }
}

nonisolated private let batchPullRequestsChunkSize = 25
nonisolated private let batchPullRequestsMaxConcurrentRequests = 3

nonisolated private func makeBranchChunks(
  _ branches: [String],
  chunkSize: Int
) -> [[String]] {
  guard !branches.isEmpty else {
    return []
  }

  var chunks: [[String]] = []
  var index = 0
  while index < branches.count {
    let end = min(index + chunkSize, branches.count)
    chunks.append(Array(branches[index..<end]))
    index = end
  }

  return chunks
}

nonisolated private func loadPullRequestChunks(
  shell: ShellClient,
  request: GithubPullRequestsRequest,
  chunks: [[String]]
) async throws -> [Int: [String: GithubPullRequest]] {
  try await withThrowingTaskGroup(
    of: (Int, [String: GithubPullRequest]).self
  ) { group in
    var nextChunkIndex = 0
    let initialCount = min(batchPullRequestsMaxConcurrentRequests, chunks.count)
    while nextChunkIndex < initialCount {
      let chunkIndex = nextChunkIndex
      let chunk = chunks[chunkIndex]
      group.addTask {
        try await fetchPullRequestsChunk(
          shell: shell,
          request: request,
          chunk: chunk,
          chunkIndex: chunkIndex
        )
      }
      nextChunkIndex += 1
    }

    var resultsByChunkIndex: [Int: [String: GithubPullRequest]] = [:]
    while let (chunkIndex, prsByBranch) = try await group.next() {
      resultsByChunkIndex[chunkIndex] = prsByBranch
      if nextChunkIndex < chunks.count {
        let candidateIndex = nextChunkIndex
        let candidateChunk = chunks[candidateIndex]
        group.addTask {
          try await fetchPullRequestsChunk(
            shell: shell,
            request: request,
            chunk: candidateChunk,
            chunkIndex: candidateIndex
          )
        }
        nextChunkIndex += 1
      }
    }

    return resultsByChunkIndex
  }
}

nonisolated private func mergePullRequestChunkResults(
  _ chunkResults: [Int: [String: GithubPullRequest]],
  chunkCount: Int
) -> [String: GithubPullRequest] {
  var results: [String: GithubPullRequest] = [:]
  for chunkIndex in 0..<chunkCount {
    guard let prsByBranch = chunkResults[chunkIndex] else {
      continue
    }
    results.merge(prsByBranch) { _, new in new }
  }
  return results
}

nonisolated private func fetchPullRequestsChunk(
  shell: ShellClient,
  request: GithubPullRequestsRequest,
  chunk: [String],
  chunkIndex: Int
) async throws -> (Int, [String: GithubPullRequest]) {
  let (query, aliasMap) = makeBatchPullRequestsQuery(branches: chunk)
  let output = try await runGh(
    shell: shell,
    arguments: [
      "api",
      "graphql",
      "--hostname",
      request.host,
      "-f",
      "query=\(query)",
      "-f",
      "owner=\(request.owner)",
      "-f",
      "repo=\(request.repo)",
    ],
    repoRoot: nil
  )
  guard !output.isEmpty else {
    return (chunkIndex, [:])
  }

  let data = Data(output.utf8)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let response = try decoder.decode(GithubGraphQLPullRequestResponse.self, from: data)
  let prsByBranch = response.pullRequestsByBranch(
    aliasMap: aliasMap,
    owner: request.owner,
    repo: request.repo
  )
  return (chunkIndex, prsByBranch)
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
    let orderBy = "orderBy: {field: UPDATED_AT, direction: DESC}"
    let selection = """
      \(alias): pullRequests(first: 5, states: [OPEN, MERGED], headRefName: \"\(escapedBranch)\", \(orderBy)) {
        nodes {
          number
          title
          state
          additions
          deletions
          isDraft
          reviewDecision
          mergeable
          mergeStateStatus
          url
          updatedAt
          headRefName
          baseRefName
          commits {
            totalCount
          }
          author {
            login
          }
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

nonisolated private func isOutdatedGitHubCLI(_ error: ShellClientError) -> Bool {
  let combined = "\(error.stdout)\n\(error.stderr)".lowercased()
  if combined.contains("unknown flag: --json") {
    return true
  }
  if combined.contains("unknown shorthand flag") && combined.contains("json") {
    return true
  }
  return false
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
      if isOutdatedGitHubCLI(shellError) {
        throw GithubCLIError.outdated
      }
      let message = shellError.errorDescription ?? "Command failed: \(command)"
      throw GithubCLIError.commandFailed(message)
    }
    throw GithubCLIError.commandFailed(error.localizedDescription)
  }
}

nonisolated private func decodeAuthStatusResponse(from data: Data) throws -> GithubAuthStatusResponse {
  try JSONDecoder().decode(GithubAuthStatusResponse.self, from: data)
}
