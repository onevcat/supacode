import Foundation

nonisolated struct GithubPullRequest: Decodable, Equatable {
  let number: Int
  let title: String
  let state: String
  let isDraft: Bool
  let reviewDecision: String?
  let updatedAt: Date?
}
