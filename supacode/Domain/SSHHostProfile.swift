import Foundation

nonisolated struct SSHHostProfile: Codable, Equatable, Sendable, Identifiable {
  enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case publicKey
    case password
  }

  var id: String
  var displayName: String
  var host: String
  var user: String
  var port: Int?
  var authMethod: AuthMethod
  var createdAt: Date
  var updatedAt: Date

  init(
    id: String = UUID().uuidString,
    displayName: String,
    host: String,
    user: String = "",
    port: Int? = nil,
    authMethod: AuthMethod,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.displayName = displayName
    self.host = host
    self.user = user
    self.port = port
    self.authMethod = authMethod
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
