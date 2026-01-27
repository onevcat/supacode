import Foundation

nonisolated enum PullRequestCheckState: Equatable {
  case passed
  case failed
  case pending
  case ignored
}

nonisolated struct PullRequestCheckSummary: Equatable {
  let passed: Int
  let failed: Int
  let pending: Int
  let ignored: Int

  var total: Int {
    passed + failed + pending
  }

  init(checks: [GithubPullRequestStatusCheck]) {
    var passed = 0
    var failed = 0
    var pending = 0
    var ignored = 0
    for check in checks {
      switch check.summarizedState {
      case .passed:
        passed += 1
      case .failed:
        failed += 1
      case .pending:
        pending += 1
      case .ignored:
        ignored += 1
      }
    }
    self.passed = passed
    self.failed = failed
    self.pending = pending
    self.ignored = ignored
  }
}

nonisolated struct GithubPullRequestStatusCheck: Decodable, Equatable {
  let status: String?
  let conclusion: String?
  let state: String?

  var summarizedState: PullRequestCheckState {
    if let status, status.uppercased() != "COMPLETED" {
      return .pending
    }
    if let state {
      switch state.uppercased() {
      case "SUCCESS":
        return .passed
      case "FAILURE", "ERROR":
        return .failed
      case "PENDING", "EXPECTED":
        return .pending
      default:
        return .pending
      }
    }
    if let conclusion {
      switch conclusion.uppercased() {
      case "SUCCESS", "NEUTRAL":
        return .passed
      case "CANCELLED", "SKIPPED":
        return .ignored
      case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE":
        return .failed
      default:
        return .pending
      }
    }
    return .pending
  }
}

nonisolated struct GithubPullRequestStatusCheckRollup: Decodable, Equatable {
  let checks: [GithubPullRequestStatusCheck]

  init(from decoder: Decoder) throws {
    if let checks = try? [GithubPullRequestStatusCheck](from: decoder) {
      self.checks = checks
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let checks = try? container.decode([GithubPullRequestStatusCheck].self, forKey: .contexts) {
      self.checks = checks
      return
    }
    if let contexts = try? container.decode(GithubPullRequestStatusCheckContexts.self, forKey: .contexts) {
      self.checks = contexts.nodes
      return
    }
    self.checks = []
  }

  private enum CodingKeys: String, CodingKey {
    case contexts
  }
}

nonisolated private struct GithubPullRequestStatusCheckContexts: Decodable, Equatable {
  let nodes: [GithubPullRequestStatusCheck]
}
