import Foundation

nonisolated struct GithubPullRequest: Decodable, Equatable, Hashable {
  let number: Int
  let title: String
  let state: String
  let additions: Int
  let deletions: Int
  let isDraft: Bool
  let reviewDecision: String?
  let updatedAt: Date?
  let url: String
  let headRefName: String?
  let statusCheckRollup: GithubPullRequestStatusCheckRollup?
}
