import SwiftUI

struct PullRequestStatusButton: View {
  let model: PullRequestStatusModel
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    PullRequestChecksPopoverButton(
      checks: model.statusChecks,
      pullRequestURL: model.url,
      pullRequestTitle: model.title
    ) {
      let breakdown = PullRequestCheckBreakdown(checks: model.statusChecks)
      let showsChecksRing = breakdown.total > 0 && model.state != "MERGED"
      HStack(spacing: 6) {
        if showsChecksRing {
          PullRequestChecksRingView(breakdown: breakdown)
        }
        PullRequestBadgeView(
          text: model.badgeText,
          color: model.badgeColor
        )
        .layoutPriority(1)
        if let detailText = model.detailText {
          Text(commandKeyObserver.isPressed ? "Open on GitHub \(AppShortcuts.openPullRequest.display)" : detailText)
            .lineLimit(1)
        } else if commandKeyObserver.isPressed {
          Text("Open on GitHub \(AppShortcuts.openPullRequest.display)")
            .lineLimit(1)
        }
        if model.detailText == nil, !commandKeyObserver.isPressed {
          Text(model.title)
            .lineLimit(1)
        }
      }
    }
    .font(.caption)
  }

}

struct PullRequestStatusModel: Equatable {
  let number: Int
  let state: String?
  let url: URL?
  let title: String
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
    self.title = pullRequest.title
    if state == "MERGED" {
      self.detailText = nil
      self.statusChecks = []
      return
    }
    let isDraft = pullRequest.isDraft
    let prefix = isDraft ? "(Drafted) " : ""
    let checks = pullRequest.statusCheckRollup?.checks ?? []
    self.statusChecks = checks
    if checks.isEmpty {
      self.detailText = isDraft ? "(Drafted)" : nil
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
