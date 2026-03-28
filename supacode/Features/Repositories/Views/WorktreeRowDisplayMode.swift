enum WorktreeRowDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case branchFirst
  case worktreeFirst

  var id: String { rawValue }

  var label: String {
    switch self {
    case .branchFirst: "Branch Name First"
    case .worktreeFirst: "Worktree Name First"
    }
  }
}
