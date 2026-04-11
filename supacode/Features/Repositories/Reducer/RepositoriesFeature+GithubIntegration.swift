import AppKit
import ComposableArchitecture
import Foundation

extension RepositoriesFeature {
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func reduceGithubIntegration(
    state: inout State,
    action: GithubIntegrationAction
  ) -> Effect<Action> {
    switch action {
    case .delayedPullRequestRefresh(let worktreeID):
      guard let worktree = state.worktree(for: worktreeID),
        let repositoryID = state.repositoryID(containing: worktreeID),
        let repository = state.repositories[id: repositoryID]
      else {
        return .none
      }
      let repositoryRootURL = worktree.repositoryRootURL
      let worktreeIDs = repository.worktrees.map(\.id)
      return .run { send in
        try? await ContinuousClock().sleep(for: .seconds(2))
        await send(
          .worktreeInfoEvent(
            .repositoryPullRequestRefresh(
              repositoryRootURL: repositoryRootURL,
              worktreeIDs: worktreeIDs
            )
          )
        )
      }
      .cancellable(id: CancelID.delayedPRRefresh(worktreeID), cancelInFlight: true)

    case .repositoryPullRequestRefreshRequested(let repositoryRootURL, let worktreeIDs):
      let worktrees = worktreeIDs.compactMap { state.worktree(for: $0) }
      guard let firstWorktree = worktrees.first,
        let repositoryID = state.repositoryID(containing: firstWorktree.id)
      else {
        return .none
      }
      var seen = Set<String>()
      let branches =
        worktrees
        .map(\.name)
        .filter { !$0.isEmpty && seen.insert($0).inserted }
      guard !branches.isEmpty else {
        return .none
      }
      switch state.githubIntegrationAvailability {
      case .available:
        if state.inFlightPullRequestRefreshRepositoryIDs.contains(repositoryID) {
          queuePullRequestRefresh(
            repositoryID: repositoryID,
            repositoryRootURL: repositoryRootURL,
            worktreeIDs: worktreeIDs,
            refreshesByRepositoryID: &state.queuedPullRequestRefreshByRepositoryID
          )
          return .none
        }
        state.inFlightPullRequestRefreshRepositoryIDs.insert(repositoryID)
        return refreshRepositoryPullRequests(
          repositoryID: repositoryID,
          repositoryRootURL: repositoryRootURL,
          worktrees: worktrees,
          branches: branches
        )
      case .unknown:
        queuePullRequestRefresh(
          repositoryID: repositoryID,
          repositoryRootURL: repositoryRootURL,
          worktreeIDs: worktreeIDs,
          refreshesByRepositoryID: &state.pendingPullRequestRefreshByRepositoryID
        )
        return .send(.githubIntegration(.refreshGithubIntegrationAvailability))
      case .checking:
        queuePullRequestRefresh(
          repositoryID: repositoryID,
          repositoryRootURL: repositoryRootURL,
          worktreeIDs: worktreeIDs,
          refreshesByRepositoryID: &state.pendingPullRequestRefreshByRepositoryID
        )
        return .none
      case .unavailable:
        queuePullRequestRefresh(
          repositoryID: repositoryID,
          repositoryRootURL: repositoryRootURL,
          worktreeIDs: worktreeIDs,
          refreshesByRepositoryID: &state.pendingPullRequestRefreshByRepositoryID
        )
        return .none
      case .disabled:
        return .none
      }

    case .refreshGithubIntegrationAvailability:
      guard state.githubIntegrationAvailability != .checking,
        state.githubIntegrationAvailability != .disabled
      else {
        return .none
      }
      state.githubIntegrationAvailability = .checking
      let githubIntegration = githubIntegration
      return .run { send in
        let isAvailable = await githubIntegration.isAvailable()
        await send(.githubIntegration(.githubIntegrationAvailabilityUpdated(isAvailable)))
      }
      .cancellable(id: CancelID.githubIntegrationAvailability, cancelInFlight: true)

    case .githubIntegrationAvailabilityUpdated(let isAvailable):
      guard state.githubIntegrationAvailability != .disabled else {
        return .none
      }
      state.githubIntegrationAvailability = isAvailable ? .available : .unavailable
      guard isAvailable else {
        for (repositoryID, queued) in state.queuedPullRequestRefreshByRepositoryID {
          queuePullRequestRefresh(
            repositoryID: repositoryID,
            repositoryRootURL: queued.repositoryRootURL,
            worktreeIDs: queued.worktreeIDs,
            refreshesByRepositoryID: &state.pendingPullRequestRefreshByRepositoryID
          )
        }
        state.queuedPullRequestRefreshByRepositoryID.removeAll()
        state.inFlightPullRequestRefreshRepositoryIDs.removeAll()
        return .run { send in
          while !Task.isCancelled {
            try? await ContinuousClock().sleep(for: githubIntegrationRecoveryInterval)
            guard !Task.isCancelled else {
              return
            }
            await send(.githubIntegration(.refreshGithubIntegrationAvailability))
          }
        }
        .cancellable(id: CancelID.githubIntegrationRecovery, cancelInFlight: true)
      }
      let pendingRefreshes = state.pendingPullRequestRefreshByRepositoryID.values.sorted {
        $0.repositoryRootURL.path(percentEncoded: false)
          < $1.repositoryRootURL.path(percentEncoded: false)
      }
      state.pendingPullRequestRefreshByRepositoryID.removeAll()
      return .merge(
        .cancel(id: CancelID.githubIntegrationRecovery),
        .merge(
          pendingRefreshes.map { pending in
            .send(
              .worktreeInfoEvent(
                .repositoryPullRequestRefresh(
                  repositoryRootURL: pending.repositoryRootURL,
                  worktreeIDs: pending.worktreeIDs
                )
              )
            )
          }
        )
      )

    case .repositoryPullRequestRefreshCompleted(let repositoryID):
      state.inFlightPullRequestRefreshRepositoryIDs.remove(repositoryID)
      guard state.githubIntegrationAvailability == .available,
        let pending = state.queuedPullRequestRefreshByRepositoryID.removeValue(
          forKey: repositoryID
        )
      else {
        return .none
      }
      return .send(
        .worktreeInfoEvent(
          .repositoryPullRequestRefresh(
            repositoryRootURL: pending.repositoryRootURL,
            worktreeIDs: pending.worktreeIDs
          )
        )
      )

    case .repositoryPullRequestsLoaded(let repositoryID, let pullRequestsByWorktreeID):
      guard let repository = state.repositories[id: repositoryID] else {
        return .none
      }
      var archiveWorktreeIDs: [Worktree.ID] = []
      for worktreeID in pullRequestsByWorktreeID.keys.sorted() {
        guard let worktree = repository.worktrees[id: worktreeID] else {
          continue
        }
        let pullRequest = pullRequestsByWorktreeID[worktreeID] ?? nil
        let previousPullRequest = state.worktreeInfoByID[worktreeID]?.pullRequest
        guard previousPullRequest != pullRequest else {
          continue
        }
        let previousMerged = previousPullRequest?.state == "MERGED"
        let nextMerged = pullRequest?.state == "MERGED"
        updateWorktreePullRequest(
          worktreeID: worktreeID,
          pullRequest: pullRequest,
          state: &state
        )
        if state.automaticallyArchiveMergedWorktrees,
          !previousMerged,
          nextMerged,
          !state.isMainWorktree(worktree),
          !state.isWorktreeArchived(worktreeID),
          !state.deletingWorktreeIDs.contains(worktreeID)
        {
          archiveWorktreeIDs.append(worktreeID)
        }
      }
      guard !archiveWorktreeIDs.isEmpty else {
        return .none
      }
      return .merge(
        archiveWorktreeIDs.map { worktreeID in
          .send(.worktreeLifecycle(.archiveWorktreeConfirmed(worktreeID, repositoryID)))
        }
      )

    case .pullRequestAction(let worktreeID, let action):
      guard let worktree = state.worktree(for: worktreeID),
        let repositoryID = state.repositoryID(containing: worktreeID),
        let repository = state.repositories[id: repositoryID],
        let pullRequest = state.worktreeInfo(for: worktreeID)?.pullRequest
      else {
        return .send(
          .presentAlert(
            title: "Pull request not available",
            message: "Prowl could not find a pull request for this worktree."
          )
        )
      }
      let repoRoot = worktree.repositoryRootURL
      let worktreeRoot = worktree.workingDirectory
      let pullRequestRefresh = WorktreeInfoWatcherClient.Event.repositoryPullRequestRefresh(
        repositoryRootURL: repoRoot,
        worktreeIDs: repository.worktrees.map(\.id)
      )
      let branchName = pullRequest.headRefName ?? worktree.name
      let failingCheckDetailsURL = (pullRequest.statusCheckRollup?.checks ?? []).first {
        $0.checkState == .failure && $0.detailsUrl != nil
      }?.detailsUrl
      switch action {
      case .openOnGithub:
        guard let url = URL(string: pullRequest.url) else {
          return .send(
            .presentAlert(
              title: "Invalid pull request URL",
              message: "Prowl could not open the pull request URL."
            )
          )
        }
        return .run { @MainActor _ in
          NSWorkspace.shared.open(url)
        }

      case .copyFailingJobURL:
        guard let failingCheckDetailsURL, !failingCheckDetailsURL.isEmpty else {
          return .send(
            .presentAlert(
              title: "Failing check not found",
              message: "Prowl could not find a failing check URL."
            )
          )
        }
        return .run { send in
          await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(failingCheckDetailsURL, forType: .string)
          }
          await send(.showToast(.success("Failing job URL copied")))
        }

      case .openFailingCheckDetails:
        guard let failingCheckDetailsURL, let url = URL(string: failingCheckDetailsURL) else {
          return .send(
            .presentAlert(
              title: "Failing check not found",
              message: "Prowl could not find a failing check with details."
            )
          )
        }
        return .run { @MainActor _ in
          NSWorkspace.shared.open(url)
        }

      case .markReadyForReview:
        let githubCLI = githubCLI
        let githubIntegration = githubIntegration
        return .run { send in
          guard await githubIntegration.isAvailable() else {
            await send(
              .presentAlert(
                title: "GitHub integration unavailable",
                message: "Enable GitHub integration to mark a pull request as ready."
              )
            )
            return
          }
          await send(.showToast(.inProgress("Marking PR ready…")))
          do {
            try await githubCLI.markPullRequestReady(worktreeRoot, pullRequest.number)
            await send(.showToast(.success("Pull request marked ready")))
            await send(.githubIntegration(.delayedPullRequestRefresh(worktreeID)))
          } catch {
            await send(.dismissToast)
            await send(
              .presentAlert(
                title: "Failed to mark pull request ready",
                message: error.localizedDescription
              )
            )
          }
        }

      case .merge:
        let githubCLI = githubCLI
        let githubIntegration = githubIntegration
        return .run { send in
          guard await githubIntegration.isAvailable() else {
            await send(
              .presentAlert(
                title: "GitHub integration unavailable",
                message: "Enable GitHub integration to merge a pull request."
              )
            )
            return
          }
          @Shared(.repositorySettings(repoRoot)) var repositorySettings
          @Shared(.settingsFile) var settingsFile
          let strategy = repositorySettings.pullRequestMergeStrategy ?? settingsFile.global.pullRequestMergeStrategy
          await send(.showToast(.inProgress("Merging pull request…")))
          do {
            try await githubCLI.mergePullRequest(worktreeRoot, pullRequest.number, strategy)
            await send(.showToast(.success("Pull request merged")))
            await send(.worktreeInfoEvent(pullRequestRefresh))
            await send(.githubIntegration(.delayedPullRequestRefresh(worktreeID)))
          } catch {
            await send(.dismissToast)
            await send(
              .presentAlert(
                title: "Failed to merge pull request",
                message: error.localizedDescription
              )
            )
          }
        }

      case .close:
        let githubCLI = githubCLI
        let githubIntegration = githubIntegration
        return .run { send in
          guard await githubIntegration.isAvailable() else {
            await send(
              .presentAlert(
                title: "GitHub integration unavailable",
                message: "Enable GitHub integration to close a pull request."
              )
            )
            return
          }
          await send(.showToast(.inProgress("Closing pull request…")))
          do {
            try await githubCLI.closePullRequest(worktreeRoot, pullRequest.number)
            await send(.showToast(.success("Pull request closed")))
            await send(.worktreeInfoEvent(pullRequestRefresh))
            await send(.githubIntegration(.delayedPullRequestRefresh(worktreeID)))
          } catch {
            await send(.dismissToast)
            await send(
              .presentAlert(
                title: "Failed to close pull request",
                message: error.localizedDescription
              )
            )
          }
        }

      case .copyCiFailureLogs:
        let githubCLI = githubCLI
        let githubIntegration = githubIntegration
        return .run { send in
          guard await githubIntegration.isAvailable() else {
            await send(
              .presentAlert(
                title: "GitHub integration unavailable",
                message: "Enable GitHub integration to copy CI failure logs."
              )
            )
            return
          }
          guard !branchName.isEmpty else {
            await send(
              .presentAlert(
                title: "Branch name unavailable",
                message: "Prowl could not determine the pull request branch."
              )
            )
            return
          }
          await send(.showToast(.inProgress("Fetching CI logs…")))
          do {
            guard let run = try await githubCLI.latestRun(worktreeRoot, branchName) else {
              await send(.dismissToast)
              await send(
                .presentAlert(
                  title: "No workflow runs found",
                  message: "Prowl could not find any workflow runs for this branch."
                )
              )
              return
            }
            guard run.conclusion?.lowercased() == "failure" else {
              await send(.dismissToast)
              await send(
                .presentAlert(
                  title: "No failing workflow run",
                  message: "Prowl could not find a failing workflow run to copy logs from."
                )
              )
              return
            }
            let failedLogs = try await githubCLI.failedRunLogs(worktreeRoot, run.databaseId)
            let logs =
              if failedLogs.isEmpty {
                try await githubCLI.runLogs(worktreeRoot, run.databaseId)
              } else {
                failedLogs
              }
            guard !logs.isEmpty else {
              await send(.dismissToast)
              await send(
                .presentAlert(
                  title: "No CI logs available",
                  message: "The workflow run failed but produced no logs."
                )
              )
              return
            }
            await MainActor.run {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(logs, forType: .string)
            }
            await send(.showToast(.success("CI failure logs copied")))
          } catch {
            await send(.dismissToast)
            await send(
              .presentAlert(
                title: "Failed to copy CI failure logs",
                message: error.localizedDescription
              )
            )
          }
        }

      case .rerunFailedJobs:
        let githubCLI = githubCLI
        let githubIntegration = githubIntegration
        return .run { send in
          guard await githubIntegration.isAvailable() else {
            await send(
              .presentAlert(
                title: "GitHub integration unavailable",
                message: "Enable GitHub integration to re-run failed jobs."
              )
            )
            return
          }
          guard !branchName.isEmpty else {
            await send(
              .presentAlert(
                title: "Branch name unavailable",
                message: "Prowl could not determine the pull request branch."
              )
            )
            return
          }
          await send(.showToast(.inProgress("Re-running failed jobs…")))
          do {
            guard let run = try await githubCLI.latestRun(worktreeRoot, branchName) else {
              await send(.dismissToast)
              await send(
                .presentAlert(
                  title: "No workflow runs found",
                  message: "Prowl could not find any workflow runs for this branch."
                )
              )
              return
            }
            guard run.conclusion?.lowercased() == "failure" else {
              await send(.dismissToast)
              await send(
                .presentAlert(
                  title: "No failing workflow run",
                  message: "Prowl could not find a failing workflow run to re-run."
                )
              )
              return
            }
            try await githubCLI.rerunFailedJobs(worktreeRoot, run.databaseId)
            await send(.showToast(.success("Failed jobs re-run started")))
            await send(.githubIntegration(.delayedPullRequestRefresh(worktreeID)))
          } catch {
            await send(.dismissToast)
            await send(
              .presentAlert(
                title: "Failed to re-run failed jobs",
                message: error.localizedDescription
              )
            )
          }
        }
      }

    case .setGithubIntegrationEnabled(let isEnabled):
      if isEnabled {
        state.githubIntegrationAvailability = .unknown
        state.pendingPullRequestRefreshByRepositoryID.removeAll()
        state.queuedPullRequestRefreshByRepositoryID.removeAll()
        state.inFlightPullRequestRefreshRepositoryIDs.removeAll()
        return .merge(
          .cancel(id: CancelID.githubIntegrationRecovery),
          .send(.githubIntegration(.refreshGithubIntegrationAvailability))
        )
      }
      state.githubIntegrationAvailability = .disabled
      state.pendingPullRequestRefreshByRepositoryID.removeAll()
      state.queuedPullRequestRefreshByRepositoryID.removeAll()
      state.inFlightPullRequestRefreshRepositoryIDs.removeAll()
      let worktreeIDs = Array(state.worktreeInfoByID.keys)
      for worktreeID in worktreeIDs {
        updateWorktreePullRequest(
          worktreeID: worktreeID,
          pullRequest: nil,
          state: &state
        )
      }
      return .merge(
        .cancel(id: CancelID.githubIntegrationAvailability),
        .cancel(id: CancelID.githubIntegrationRecovery)
      )

    case .setAutomaticallyArchiveMergedWorktrees(let isEnabled):
      state.automaticallyArchiveMergedWorktrees = isEnabled
      return .none
    }
  }

  var githubIntegrationReducer: some ReducerOf<Self> {
    Reduce { state, action in
      guard case .githubIntegration(let action) = action else {
        return .none
      }
      return reduceGithubIntegration(state: &state, action: action)
    }
  }
}
