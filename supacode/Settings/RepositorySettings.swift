import Foundation

nonisolated struct RepositorySettings: Codable, Equatable {
  var startupCommand: String

  static let `default` = RepositorySettings(startupCommand: "echo 123")
}
