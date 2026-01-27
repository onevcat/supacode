import CustomDump
import Foundation

extension Repository: CustomDumpRepresentable {
  var customDumpValue: Any {
    (
      name: name,
      worktrees: worktrees.count
    )
  }
}

extension Worktree: CustomDumpRepresentable {
  var customDumpValue: Any {
    (
      id: id,
      name: name,
      detail: detail
    )
  }
}

extension WorktreeInfoSnapshot: CustomDumpRepresentable {
  var customDumpValue: Any {
    (
      repositoryName: repositoryName,
      pr: pullRequestNumber.map { "#\($0)" },
      prState: pullRequestState,
      isDraft: pullRequestIsDraft,
      reviewDecision: pullRequestReviewDecision,
      workflow: workflowStatus,
      conclusion: workflowConclusion,
      githubError: githubError,
      ciError: ciError
    )
  }
}

extension RepositoriesFeature.State: CustomDumpRepresentable {
  var customDumpValue: Any {
    (
      repositories: repositories.count,
      selectedWorktreeID: selectedWorktreeID,
      pending: pendingWorktrees.count,
      deleting: deletingWorktreeIDs.count,
      hasAlert: alert != nil
    )
  }
}
