import SwiftUI

struct PullRequestStatusButton: View {
  let model: PullRequestStatusModel
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    PullRequestChecksPopoverButton(
      checks: model.statusChecks,
      pullRequestURL: model.url
    ) {
      let breakdown = PullRequestCheckBreakdown(checks: model.statusChecks)
      HStack(spacing: 6) {
        PullRequestChecksRingView(breakdown: breakdown)
        PullRequestBadgeView(
          text: model.badgeText,
          color: model.badgeColor
        )
        if let detailText = model.detailText {
          Text(commandKeyObserver.isPressed ? "Open on GitHub \(AppShortcuts.openPullRequest.display)" : detailText)
        } else if commandKeyObserver.isPressed {
          Text("Open on GitHub \(AppShortcuts.openPullRequest.display)")
        }
      }
    }
    .font(.caption)
    .monospaced()
  }

}

struct PullRequestStatusModel: Equatable {
  let number: Int
  let state: String?
  let url: URL?
  let statusChecks: [GithubPullRequestStatusCheck]
  let detailText: String?

  init?(pullRequest: GithubPullRequest?) {
    guard
      let pullRequest,
      Self.shouldDisplay(state: pullRequest.state, number: pullRequest.number)
    else {
      return nil
    }
    self.number = pullRequest.number
    let state = pullRequest.state.uppercased()
    self.state = state
    self.url = URL(string: pullRequest.url)
    if state == "MERGED" {
      self.detailText = "Merged"
      self.statusChecks = []
      return
    }
    let isDraft = pullRequest.isDraft
    let prefix = isDraft ? "(Drafted) " : ""
    let checks = pullRequest.statusCheckRollup?.checks ?? []
    self.statusChecks = checks
    if checks.isEmpty {
      self.detailText = prefix + "Checks unavailable"
      return
    }
    let breakdown = PullRequestCheckBreakdown(checks: checks)
    let checksLabel = breakdown.total == 1 ? "check" : "checks"
    self.detailText = prefix + breakdown.summaryText + " \(checksLabel)"
  }

  var badgeText: String {
    PullRequestBadgeStyle.style(state: state, number: number)?.text ?? "#\(number)"
  }

  var badgeColor: Color {
    PullRequestBadgeStyle.style(state: state, number: number)?.color ?? .secondary
  }

  static func shouldDisplay(state: String?, number: Int?) -> Bool {
    guard number != nil else {
      return false
    }
    return state?.uppercased() != "CLOSED"
  }
}
