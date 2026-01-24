import ComposableArchitecture
import Foundation

@Reducer
struct WorktreeInfoFeature {
  @ObservableState
  struct State: Equatable {
    var worktree: Worktree?
    var snapshot: WorktreeInfoSnapshot?
    var status: WorktreeInfoStatus = .idle
    var lastRefresh: Date?
    var cachedSnapshots: [Worktree.ID: WorktreeInfoSnapshot] = [:]
    var cachedRefreshDates: [Worktree.ID: Date] = [:]
  }

  enum Action: Equatable {
    case task
    case worktreeChanged(Worktree?)
    case refresh
    case refreshFinished(Result<WorktreeInfoSnapshot, WorktreeInfoError>)
    case timerTick
    case appBecameActive
  }

  @Dependency(\.shellClient) private var shellClient
  @Dependency(\.githubCLI) private var githubCLI
  @Dependency(\.continuousClock) private var clock

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        return .none

      case .worktreeChanged(let worktree):
        state.worktree = worktree
        if let worktree {
          state.snapshot = state.cachedSnapshots[worktree.id]
          state.lastRefresh = state.cachedRefreshDates[worktree.id]
          state.status = state.snapshot == nil ? .loading : .idle
        } else {
          state.snapshot = nil
          state.lastRefresh = nil
          state.status = .idle
        }
        if worktree == nil {
          return .merge(
            .cancel(id: WorktreeInfoCancelID.refresh),
            .cancel(id: WorktreeInfoCancelID.timer)
          )
        }
        return .merge(
          .cancel(id: WorktreeInfoCancelID.refresh),
          timerEffect(),
          .send(.refresh)
        )

      case .refresh:
        guard let worktree = state.worktree else { return .none }
        state.status = .loading
        let shellClient = shellClient
        let githubCLI = githubCLI
        return .run { send in
          let result: Result<WorktreeInfoSnapshot, WorktreeInfoError> = await Result {
            try await loadWorktreeInfoSnapshot(
              worktree: worktree,
              shellClient: shellClient,
              githubCLI: githubCLI
            )
          }.mapError { error in
            if let githubError = error as? GithubCLIError {
              return .githubFailure(githubError.localizedDescription)
            }
            if let shellError = error as? ShellClientError {
              return .gitFailure(shellError.localizedDescription)
            }
            return .gitFailure(error.localizedDescription)
          }
          await send(.refreshFinished(result))
        }
        .cancellable(id: WorktreeInfoCancelID.refresh, cancelInFlight: true)

      case .refreshFinished(let result):
        switch result {
        case .success(let snapshot):
          state.snapshot = snapshot
          state.status = .idle
          let refreshedAt = Date()
          state.lastRefresh = refreshedAt
          if let worktree = state.worktree {
            state.cachedSnapshots[worktree.id] = snapshot
            state.cachedRefreshDates[worktree.id] = refreshedAt
          }
        case .failure(let error):
          state.status = .failed(error.localizedDescription)
        }
        return .none

      case .timerTick:
        return .send(.refresh)

      case .appBecameActive:
        guard state.worktree != nil else { return .none }
        return .send(.refresh)
      }
    }
  }

  private func timerEffect() -> Effect<Action> {
    .run { send in
      while !Task.isCancelled {
        try await clock.sleep(for: .seconds(60))
        await send(.timerTick)
      }
    }
    .cancellable(id: WorktreeInfoCancelID.timer, cancelInFlight: true)
  }
}

nonisolated private func loadWorktreeInfoSnapshot(
  worktree: Worktree,
  shellClient: ShellClient,
  githubCLI: GithubCLIClient
) async throws -> WorktreeInfoSnapshot {
  let repoRoot = worktree.repositoryRootURL
  let worktreeRoot = worktree.workingDirectory
  let repositoryName = repoRoot.lastPathComponent
  let repositoryPath = repoRoot.path(percentEncoded: false)
  let worktreePath = worktreeRoot.path(percentEncoded: false)

  let statusOutput = try await runGit(
    ["status", "--porcelain=v2", "--branch"],
    in: worktreeRoot,
    shellClient: shellClient
  )
  let statusSummary = parseGitStatusV2(statusOutput)
  let branchHead = statusSummary.branchHead ?? "HEAD"
  let isDetachedHead = branchHead == "(detached)"
  let branchName: String
  if isDetachedHead {
    branchName = statusSummary.shortOid ?? "HEAD"
  } else {
    branchName = branchHead
  }

  var githubError: String?
  var ciError: String?
  let githubAvailable = await githubCLI.isAvailable()
  if !githubAvailable {
    githubError = GithubCLIError.unavailable.errorDescription
  }

  var defaultBranchName: String?
  if githubAvailable {
    do {
      defaultBranchName = try await githubCLI.defaultBranch(repoRoot)
    } catch {
      githubError = githubError ?? error.localizedDescription
    }
  }
  if defaultBranchName == nil {
    let symbolicRef = try? await runGit(
      ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
      in: repoRoot,
      shellClient: shellClient
    )
    if let symbolicRef, !symbolicRef.isEmpty {
      defaultBranchName = parseDefaultBranchFromSymbolicRef(symbolicRef)
    }
  }
  if defaultBranchName == nil {
    let localBranches = try? await runGit(
      ["for-each-ref", "--format=%(refname:short)", "refs/heads"],
      in: repoRoot,
      shellClient: shellClient
    )
    if let localBranches {
      let branches = localBranches
        .split(whereSeparator: \.isNewline)
        .map { String($0) }
      if branches.contains("main") {
        defaultBranchName = "main"
      } else if branches.contains("master") {
        defaultBranchName = "master"
      } else {
        defaultBranchName = branches.first
      }
    }
  }

  var defaultRef: String?
  if let defaultBranchName {
    let remoteRef = "refs/remotes/origin/\(defaultBranchName)"
    if await gitRefExists(remoteRef, in: repoRoot, shellClient: shellClient) {
      defaultRef = "origin/\(defaultBranchName)"
    } else if await gitRefExists("refs/heads/\(defaultBranchName)", in: repoRoot, shellClient: shellClient) {
      defaultRef = defaultBranchName
    }
  }

  var aheadOfDefault: Int?
  var behindDefault: Int?
  if let defaultRef {
    let output = try? await runGit(
      ["rev-list", "--left-right", "--count", "\(defaultRef)...HEAD"],
      in: worktreeRoot,
      shellClient: shellClient
    )
    if let output, let counts = parseAheadBehindCounts(output) {
      behindDefault = counts.behind
      aheadOfDefault = counts.ahead
    }
  }

  let outOfDateWithDefault = behindDefault.map { $0 > 0 }

  let upstreamBranchName = statusSummary.upstream
  let aheadOfUpstream = statusSummary.ahead
  let behindUpstream = statusSummary.behind
  let hasUncommittedChanges =
    statusSummary.staged > 0 || statusSummary.unstaged > 0 || statusSummary.untracked > 0

  let stashOutput = try? await runGit(
    ["stash", "list"],
    in: worktreeRoot,
    shellClient: shellClient
  )
  let stashCount = stashOutput?.isEmpty == false
    ? stashOutput?.split(whereSeparator: \.isNewline).count ?? 0
    : 0

  let lastCommitOutput = try? await runGit(
    ["log", "-1", "--pretty=format:%s%n%ct"],
    in: worktreeRoot,
    shellClient: shellClient
  )
  var lastCommitSubject: String?
  var lastCommitDate: Date?
  if let lastCommitOutput, !lastCommitOutput.isEmpty {
    let parts = lastCommitOutput.split(whereSeparator: \.isNewline)
    if let subject = parts.first {
      lastCommitSubject = String(subject)
    }
    if parts.count > 1, let timestamp = TimeInterval(parts[1]) {
      lastCommitDate = Date(timeIntervalSince1970: timestamp)
    }
  }

  var mergeConflictPossible: Bool?
  if let defaultRef {
    if let base = try? await runGit(
      ["merge-base", "HEAD", defaultRef],
      in: worktreeRoot,
      shellClient: shellClient
    ), !base.isEmpty {
      let mergeOutput = try? await runGit(
        ["merge-tree", base, "HEAD", defaultRef],
        in: worktreeRoot,
        shellClient: shellClient
      )
      if let mergeOutput {
        mergeConflictPossible = parseMergeTreeConflict(mergeOutput)
      }
    }
  }

  var remoteBranchExists: Bool?
  if !branchName.isEmpty {
    let output = try? await runGit(
      ["ls-remote", "--heads", "origin", branchName],
      in: repoRoot,
      shellClient: shellClient
    )
    if let output {
      remoteBranchExists = !output.isEmpty
    }
  }

  var pullRequestNumber: Int?
  var pullRequestTitle: String?
  var pullRequestState: String?
  var pullRequestIsDraft = false
  var pullRequestReviewDecision: String?
  var pullRequestUpdatedAt: Date?

  if githubAvailable, !isDetachedHead {
    do {
      if let pr = try await githubCLI.pullRequest(repoRoot, branchName) {
        pullRequestNumber = pr.number
        pullRequestTitle = pr.title
        pullRequestState = pr.state
        pullRequestIsDraft = pr.isDraft
        pullRequestReviewDecision = pr.reviewDecision
        pullRequestUpdatedAt = pr.updatedAt
      }
    } catch {
      githubError = githubError ?? error.localizedDescription
    }
  }

  var workflowName: String?
  var workflowStatus: String?
  var workflowConclusion: String?
  var workflowUpdatedAt: Date?

  if githubAvailable, !isDetachedHead {
    do {
      if let run = try await githubCLI.latestRun(repoRoot, branchName) {
        workflowName = run.workflowName ?? run.name ?? run.displayTitle
        workflowStatus = run.status
        workflowConclusion = run.conclusion
        workflowUpdatedAt = run.updatedAt ?? run.createdAt
      }
    } catch {
      ciError = error.localizedDescription
    }
  }

  return WorktreeInfoSnapshot(
    repositoryName: repositoryName,
    repositoryPath: repositoryPath,
    worktreePath: worktreePath,
    branchName: branchName,
    isDetachedHead: isDetachedHead,
    defaultBranchName: defaultBranchName,
    aheadOfDefault: aheadOfDefault,
    behindDefault: behindDefault,
    outOfDateWithDefault: outOfDateWithDefault,
    upstreamBranchName: upstreamBranchName,
    aheadOfUpstream: aheadOfUpstream,
    behindUpstream: behindUpstream,
    remoteBranchExists: remoteBranchExists,
    hasUncommittedChanges: hasUncommittedChanges,
    stagedChanges: statusSummary.staged,
    unstagedChanges: statusSummary.unstaged,
    untrackedChanges: statusSummary.untracked,
    stashCount: stashCount,
    lastCommitSubject: lastCommitSubject,
    lastCommitDate: lastCommitDate,
    mergeConflictPossible: mergeConflictPossible,
    pullRequestNumber: pullRequestNumber,
    pullRequestTitle: pullRequestTitle,
    pullRequestState: pullRequestState,
    pullRequestIsDraft: pullRequestIsDraft,
    pullRequestReviewDecision: pullRequestReviewDecision,
    pullRequestUpdatedAt: pullRequestUpdatedAt,
    workflowName: workflowName,
    workflowStatus: workflowStatus,
    workflowConclusion: workflowConclusion,
    workflowUpdatedAt: workflowUpdatedAt,
    githubError: githubError,
    ciError: ciError
  )
}

nonisolated private func runGit(
  _ arguments: [String],
  in directory: URL,
  shellClient: ShellClient
) async throws -> String {
  let env = URL(fileURLWithPath: "/usr/bin/env")
  return try await shellClient.run(env, ["git"] + arguments, directory).stdout
}

nonisolated private func gitRefExists(
  _ ref: String,
  in directory: URL,
  shellClient: ShellClient
) async -> Bool {
  do {
    _ = try await runGit(["show-ref", "--verify", "--quiet", ref], in: directory, shellClient: shellClient)
    return true
  } catch {
    return false
  }
}
