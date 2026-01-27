import Foundation

nonisolated struct WorktreeInfoSnapshot: Equatable {
  let repositoryName: String
  let repositoryPath: String
  let worktreePath: String
  let defaultBranchName: String?
  let pullRequestNumber: Int?
  let pullRequestTitle: String?
  let pullRequestURL: String?
  let pullRequestState: String?
  let pullRequestIsDraft: Bool
  let pullRequestReviewDecision: String?
  let pullRequestUpdatedAt: Date?
  let pullRequestStatusChecks: [GithubPullRequestStatusCheck]
  let workflowName: String?
  let workflowStatus: String?
  let workflowConclusion: String?
  let workflowUpdatedAt: Date?
  let githubError: String?
  let ciError: String?
}
