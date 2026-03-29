import Foundation

nonisolated struct PersistedRepositoryEntry: Codable, Equatable, Sendable {
  let path: String
  let kind: Repository.Kind
  let endpoint: RepositoryEndpoint

  init(
    path: String,
    kind: Repository.Kind,
    endpoint: RepositoryEndpoint = .local
  ) {
    self.path = path
    self.kind = kind
    self.endpoint = endpoint
  }

  enum CodingKeys: String, CodingKey {
    case path
    case kind
    case endpoint
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    kind = try container.decode(Repository.Kind.self, forKey: .kind)
    endpoint = try container.decodeIfPresent(RepositoryEndpoint.self, forKey: .endpoint) ?? .local
  }
}
