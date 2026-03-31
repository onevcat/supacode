nonisolated struct SettingsFile: Codable, Equatable, Sendable {
  var global: GlobalSettings
  var sshHostProfiles: [SSHHostProfile]
  var repositories: [String: RepositorySettings]
  var repositoryRoots: [String]
  var pinnedWorktreeIDs: [Worktree.ID]

  enum CodingKeys: String, CodingKey {
    case global
    case sshHostProfiles
    case repositories
    case repositoryRoots
    case pinnedWorktreeIDs
  }

  static let `default` = SettingsFile(
    global: .default,
    sshHostProfiles: [],
    repositories: [:],
    repositoryRoots: [],
    pinnedWorktreeIDs: []
  )

  init(
    global: GlobalSettings = .default,
    sshHostProfiles: [SSHHostProfile] = [],
    repositories: [String: RepositorySettings] = [:],
    repositoryRoots: [String] = [],
    pinnedWorktreeIDs: [Worktree.ID] = []
  ) {
    self.global = global
    self.sshHostProfiles = sshHostProfiles
    self.repositories = repositories
    self.repositoryRoots = repositoryRoots
    self.pinnedWorktreeIDs = pinnedWorktreeIDs
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    global = try container.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? .default
    sshHostProfiles =
      try container.decodeIfPresent([SSHHostProfile].self, forKey: .sshHostProfiles) ?? []
    repositories =
      try container.decodeIfPresent([String: RepositorySettings].self, forKey: .repositories)
      ?? [:]
    repositoryRoots = try container.decodeIfPresent([String].self, forKey: .repositoryRoots) ?? []
    pinnedWorktreeIDs =
      try container.decodeIfPresent([Worktree.ID].self, forKey: .pinnedWorktreeIDs) ?? []
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(global, forKey: .global)
    try container.encode(sshHostProfiles, forKey: .sshHostProfiles)
    try container.encode(repositories, forKey: .repositories)
    try container.encode(repositoryRoots, forKey: .repositoryRoots)
    try container.encode(pinnedWorktreeIDs, forKey: .pinnedWorktreeIDs)
  }
}
