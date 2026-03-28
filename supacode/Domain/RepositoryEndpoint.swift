import Foundation

nonisolated enum RepositoryEndpoint: Equatable, Hashable, Sendable {
  case local
  case remote(hostProfileID: String, remotePath: String)

  var isRemote: Bool {
    if case .remote = self {
      return true
    }
    return false
  }
}

extension RepositoryEndpoint: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case hostProfileID
    case remotePath
  }

  private enum Kind: String, Codable {
    case local
    case remote
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    switch kind {
    case .local:
      self = .local
    case .remote:
      let hostProfileID = try container.decode(String.self, forKey: .hostProfileID)
      let remotePath = try container.decode(String.self, forKey: .remotePath)
      self = .remote(hostProfileID: hostProfileID, remotePath: remotePath)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .local:
      try container.encode(Kind.local, forKey: .kind)
    case .remote(let hostProfileID, let remotePath):
      try container.encode(Kind.remote, forKey: .kind)
      try container.encode(hostProfileID, forKey: .hostProfileID)
      try container.encode(remotePath, forKey: .remotePath)
    }
  }
}
