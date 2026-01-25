import Foundation

nonisolated struct RepositorySettings: Codable, Equatable {
  var setupScript: String
  var openActionID: String

  private enum CodingKeys: String, CodingKey {
    case setupScript
    case openActionID
  }

  static let `default` = RepositorySettings(
    setupScript: "echo \"Setup your startup script in repo settings\"",
    openActionID: "finder"
  )

  init(setupScript: String, openActionID: String) {
    self.setupScript = setupScript
    self.openActionID = openActionID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    setupScript = try container.decodeIfPresent(String.self, forKey: .setupScript)
      ?? Self.default.setupScript
    openActionID = try container.decodeIfPresent(String.self, forKey: .openActionID)
      ?? Self.default.openActionID
  }
}
