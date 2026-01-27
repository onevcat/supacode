import SwiftUI

struct PullRequestStatusButton: View {
  let model: PullRequestStatusModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button(model.label) {
      if let url = model.url {
        openURL(url)
      }
    }
    .buttonStyle(.plain)
    .font(.caption)
    .monospaced()
    .help("Open pull request on GitHub")
  }
}

struct PullRequestStatusModel: Equatable {
  let label: String
  let url: URL?

  init?(snapshot: WorktreeInfoSnapshot?) {
    guard let snapshot, let number = snapshot.pullRequestNumber else {
      return nil
    }
    let state = snapshot.pullRequestState?.uppercased()
    if state == "CLOSED" {
      return nil
    }
    let url = snapshot.pullRequestURL.flatMap(URL.init(string:))
    if state == "MERGED" {
      self.label = "PR #\(number) - Merged"
      self.url = url
      return
    }
    let isDraft = snapshot.pullRequestIsDraft
    let prefix = "PR #\(number)\(isDraft ? " (Drafted)" : "") ↗ - "
    let checks = snapshot.pullRequestStatusChecks
    if checks.isEmpty {
      self.label = prefix + "Checks unavailable"
      self.url = url
      return
    }
    let summary = PullRequestCheckSummary(checks: checks)
    if summary.failed > 0 {
      self.label = prefix + "\(summary.failed)/\(summary.total) checks failed"
      self.url = url
      return
    }
    let pendingCount = summary.pending + summary.ignored
    if pendingCount > 0 {
      self.label = prefix + "\(pendingCount) checks pending"
      self.url = url
      return
    }
    self.label = prefix + "All checks passed"
    self.url = url
  }
}
