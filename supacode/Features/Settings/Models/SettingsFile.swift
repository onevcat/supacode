nonisolated struct SettingsFile: Codable, Equatable, Sendable {
  var global: GlobalSettings
  var repositories: [String: RepositorySettings]
  var repositoryRoots: [String]
  var pinnedWorktreeIDs: [Worktree.ID]
  var lastFocusedWorktreeID: Worktree.ID?

  enum CodingKeys: String, CodingKey {
    case global
    case repositories
    case repositoryRoots
    case pinnedWorktreeIDs
    case lastFocusedWorktreeID
  }

  static let `default` = SettingsFile(
    global: .default,
    repositories: [:],
    repositoryRoots: [],
    pinnedWorktreeIDs: [],
    lastFocusedWorktreeID: nil
  )

  init(
    global: GlobalSettings = .default,
    repositories: [String: RepositorySettings] = [:],
    repositoryRoots: [String] = [],
    pinnedWorktreeIDs: [Worktree.ID] = [],
    lastFocusedWorktreeID: Worktree.ID? = nil
  ) {
    self.global = global
    self.repositories = repositories
    self.repositoryRoots = repositoryRoots
    self.pinnedWorktreeIDs = pinnedWorktreeIDs
    self.lastFocusedWorktreeID = lastFocusedWorktreeID
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    global = try container.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? .default
    repositories =
      try container.decodeIfPresent([String: RepositorySettings].self, forKey: .repositories)
      ?? [:]
    repositoryRoots = try container.decodeIfPresent([String].self, forKey: .repositoryRoots) ?? []
    pinnedWorktreeIDs =
      try container.decodeIfPresent([Worktree.ID].self, forKey: .pinnedWorktreeIDs) ?? []
    lastFocusedWorktreeID =
      try container.decodeIfPresent(Worktree.ID.self, forKey: .lastFocusedWorktreeID)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(global, forKey: .global)
    try container.encode(repositories, forKey: .repositories)
    try container.encode(repositoryRoots, forKey: .repositoryRoots)
    try container.encode(pinnedWorktreeIDs, forKey: .pinnedWorktreeIDs)
    try container.encode(lastFocusedWorktreeID, forKey: .lastFocusedWorktreeID)
  }
}
