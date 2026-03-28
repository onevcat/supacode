import Foundation

nonisolated struct Worktree: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let detail: String
  let workingDirectory: URL
  let repositoryRootURL: URL
  let endpoint: RepositoryEndpoint
  let createdAt: Date?

  nonisolated init(
    id: String,
    name: String,
    detail: String,
    workingDirectory: URL,
    repositoryRootURL: URL,
    endpoint: RepositoryEndpoint = .local,
    createdAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.detail = detail
    self.workingDirectory = workingDirectory
    self.repositoryRootURL = repositoryRootURL
    self.endpoint = endpoint
    self.createdAt = createdAt
  }
}
