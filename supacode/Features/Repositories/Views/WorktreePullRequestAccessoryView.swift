import SwiftUI

struct WorktreePullRequestDisplay {
  let pullRequest: GithubPullRequest?
  let pullRequestState: String?
  let pullRequestChecks: [GithubPullRequestStatusCheck]
  let pullRequestBadgeStyle: (text: String, color: Color)?

  init(worktreeName: String, pullRequest: GithubPullRequest?) {
    let matchesWorktree =
      if let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == worktreeName
      } else {
        false
      }
    let displayPullRequest = matchesWorktree ? pullRequest : nil
    let pullRequestState = displayPullRequest?.state.uppercased()
    let pullRequestNumber = displayPullRequest?.number
    self.pullRequest = displayPullRequest
    self.pullRequestState = pullRequestState
    self.pullRequestChecks = displayPullRequest?.statusCheckRollup?.checks ?? []
    self.pullRequestBadgeStyle = PullRequestBadgeStyle.style(
      state: pullRequestState,
      number: pullRequestNumber
    )
  }
}

struct WorktreePullRequestAccessoryView: View {
  let display: WorktreePullRequestDisplay

  var body: some View {
    if let pullRequestBadgeStyle = display.pullRequestBadgeStyle,
      let pullRequest = display.pullRequest
    {
      PullRequestChecksPopoverButton(
        pullRequest: pullRequest
      ) {
        let breakdown = PullRequestCheckBreakdown(checks: display.pullRequestChecks)
        let showsChecksRing = breakdown.total > 0 && display.pullRequestState != "MERGED"
        HStack(spacing: 6) {
          if showsChecksRing {
            PullRequestChecksRingView(breakdown: breakdown)
          }
          PullRequestBadgeView(text: pullRequestBadgeStyle.text, color: pullRequestBadgeStyle.color)
        }
      }
    }
  }
}
