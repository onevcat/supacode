nonisolated struct WorktreeCreationProgress: Hashable, Sendable {
  var stage: WorktreeCreationStage
  var worktreeName: String?
  var baseRef: String?
  var copyIgnored: Bool?
  var copyUntracked: Bool?
  var ignoredFilesToCopyCount: Int?
  var untrackedFilesToCopyCount: Int?

  init(
    stage: WorktreeCreationStage,
    worktreeName: String? = nil,
    baseRef: String? = nil,
    copyIgnored: Bool? = nil,
    copyUntracked: Bool? = nil,
    ignoredFilesToCopyCount: Int? = nil,
    untrackedFilesToCopyCount: Int? = nil
  ) {
    self.stage = stage
    self.worktreeName = worktreeName
    self.baseRef = baseRef
    self.copyIgnored = copyIgnored
    self.copyUntracked = copyUntracked
    self.ignoredFilesToCopyCount = ignoredFilesToCopyCount
    self.untrackedFilesToCopyCount = untrackedFilesToCopyCount
  }

  var titleText: String {
    if let worktreeName, !worktreeName.isEmpty {
      return "Creating \(worktreeName)"
    }
    return "Creating worktree"
  }

  var detailText: String {
    switch stage {
    case .loadingLocalBranches:
      return "Reading local branches"
    case .choosingWorktreeName:
      return "Choosing available worktree name"
    case .checkingRepositoryMode:
      return "Checking repository mode"
    case .resolvingBaseReference:
      return "Resolving base reference (\(baseRefDisplay))"
    case .creatingWorktree:
      let ignoredCount = copyIgnored == true ? (ignoredFilesToCopyCount ?? 0) : 0
      let untrackedCount = copyUntracked == true ? (untrackedFilesToCopyCount ?? 0) : 0
      let copySummary =
        "Copying \(ignoredCount) ignored files and copying \(untrackedCount) untracked files"
      return
        "Creating from \(baseRefBranchDisplay). \(copySummary)"
    }
  }

  private var baseRefDisplay: String {
    guard let baseRef, !baseRef.isEmpty else {
      return "HEAD"
    }
    return baseRef
  }

  private var baseRefBranchDisplay: String {
    let normalized = baseRefDisplay.lowercased()
    if normalized == "main" || normalized == "origin/main" {
      return "main branch"
    }
    if normalized == "head" {
      return "HEAD"
    }
    return "\(baseRefDisplay) branch"
  }
}

nonisolated enum WorktreeCreationStage: Hashable, Sendable {
  case loadingLocalBranches
  case choosingWorktreeName
  case checkingRepositoryMode
  case resolvingBaseReference
  case creatingWorktree
}
