import ComposableArchitecture
import Foundation

@Reducer
struct WorktreeInfoFeature {
  @ObservableState
  struct State: Equatable {
    var worktree: Worktree?
    var snapshot: WorktreeInfoSnapshot?
    var status: WorktreeInfoStatus = .idle
    var nextRefresh: Date?
    var cachedSnapshots: [Worktree.ID: WorktreeInfoSnapshot] = [:]
    var cachedNextRefreshDates: [Worktree.ID: Date] = [:]
  }

  enum Action: Equatable {
    case task
    case worktreeChanged(Worktree?)
    case refresh
    case refreshFinished(Result<WorktreeInfoSnapshot, WorktreeInfoError>)
    case timerTick
    case appBecameActive
  }

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
          state.nextRefresh = state.cachedNextRefreshDates[worktree.id]
          state.status = state.snapshot == nil ? .loading : .idle
        } else {
          state.snapshot = nil
          state.nextRefresh = nil
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
        let githubCLI = githubCLI
        return .run { send in
          let result: Result<WorktreeInfoSnapshot, WorktreeInfoError> = await Result {
            try await loadWorktreeInfoSnapshot(
              worktree: worktree,
              githubCLI: githubCLI
            )
          }.mapError { error in
            if let githubError = error as? GithubCLIError {
              return .githubFailure(githubError.localizedDescription)
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
          let nextRefresh = Date().addingTimeInterval(60)
          state.nextRefresh = nextRefresh
          if let worktree = state.worktree {
            state.cachedSnapshots[worktree.id] = snapshot
            state.cachedNextRefreshDates[worktree.id] = nextRefresh
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
  githubCLI: GithubCLIClient
) async throws -> WorktreeInfoSnapshot {
  let repoRoot = worktree.repositoryRootURL
  let repositoryName = repoRoot.lastPathComponent
  let repositoryPath = repoRoot.path(percentEncoded: false)
  let worktreeRoot = worktree.workingDirectory
  let worktreePath = worktreeRoot.path(percentEncoded: false)

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
      githubError = "Not a GitHub repository"
    }
  }
  var workflowName: String?
  var workflowStatus: String?
  var workflowConclusion: String?
  var workflowUpdatedAt: Date?

  var pullRequestNumber: Int?
  var pullRequestTitle: String?
  var pullRequestURL: String?
  var pullRequestState: String?
  var pullRequestIsDraft = false
  var pullRequestReviewDecision: String?
  var pullRequestUpdatedAt: Date?
  var pullRequestStatusChecks: [GithubPullRequestStatusCheck] = []

  if githubAvailable {
    do {
      if let pullRequest = try await githubCLI.currentPullRequest(worktreeRoot) {
        pullRequestNumber = pullRequest.number
        pullRequestTitle = pullRequest.title
        pullRequestURL = pullRequest.url
        pullRequestState = pullRequest.state
        pullRequestIsDraft = pullRequest.isDraft
        pullRequestReviewDecision = pullRequest.reviewDecision
        pullRequestUpdatedAt = pullRequest.updatedAt
        pullRequestStatusChecks = pullRequest.statusCheckRollup?.checks ?? []
      }
    } catch {
      githubError = githubError ?? error.localizedDescription
    }
  }

  if githubAvailable, let defaultBranchName {
    do {
      if let run = try await githubCLI.latestRun(repoRoot, defaultBranchName) {
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
    defaultBranchName: defaultBranchName,
    pullRequestNumber: pullRequestNumber,
    pullRequestTitle: pullRequestTitle,
    pullRequestURL: pullRequestURL,
    pullRequestState: pullRequestState,
    pullRequestIsDraft: pullRequestIsDraft,
    pullRequestReviewDecision: pullRequestReviewDecision,
    pullRequestUpdatedAt: pullRequestUpdatedAt,
    pullRequestStatusChecks: pullRequestStatusChecks,
    workflowName: workflowName,
    workflowStatus: workflowStatus,
    workflowConclusion: workflowConclusion,
    workflowUpdatedAt: workflowUpdatedAt,
    githubError: githubError,
    ciError: ciError
  )
}
