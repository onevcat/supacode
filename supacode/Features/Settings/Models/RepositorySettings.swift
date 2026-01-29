import Foundation

nonisolated struct RepositorySettings: Codable, Equatable, Sendable {
  var setupScript: String
  var runScript: String
  var openActionID: String
  var copyIgnoredOnWorktreeCreate: Bool
  var copyUntrackedOnWorktreeCreate: Bool

  private enum CodingKeys: String, CodingKey {
    case setupScript
    case runScript
    case openActionID
    case copyIgnoredOnWorktreeCreate
    case copyUntrackedOnWorktreeCreate
  }

  static let `default` = RepositorySettings(
    setupScript: "echo \"Setup your startup script in repo settings\"",
    runScript: "echo \"Configure run script in Settings, default hot key is CMD+R and CMD + . to stop\"",
    openActionID: OpenWorktreeAction.automaticSettingsID,
    copyIgnoredOnWorktreeCreate: false,
    copyUntrackedOnWorktreeCreate: false
  )

  init(
    setupScript: String,
    runScript: String,
    openActionID: String,
    copyIgnoredOnWorktreeCreate: Bool,
    copyUntrackedOnWorktreeCreate: Bool
  ) {
    self.setupScript = setupScript
    self.runScript = runScript
    self.openActionID = openActionID
    self.copyIgnoredOnWorktreeCreate = copyIgnoredOnWorktreeCreate
    self.copyUntrackedOnWorktreeCreate = copyUntrackedOnWorktreeCreate
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    setupScript = try container.decodeIfPresent(String.self, forKey: .setupScript)
      ?? Self.default.setupScript
    runScript = try container.decodeIfPresent(String.self, forKey: .runScript)
      ?? Self.default.runScript
    openActionID = try container.decodeIfPresent(String.self, forKey: .openActionID)
      ?? Self.default.openActionID
    copyIgnoredOnWorktreeCreate = try container.decodeIfPresent(
      Bool.self,
      forKey: .copyIgnoredOnWorktreeCreate
    ) ?? Self.default.copyIgnoredOnWorktreeCreate
    copyUntrackedOnWorktreeCreate = try container.decodeIfPresent(
      Bool.self,
      forKey: .copyUntrackedOnWorktreeCreate
    ) ?? Self.default.copyUntrackedOnWorktreeCreate
  }
}
