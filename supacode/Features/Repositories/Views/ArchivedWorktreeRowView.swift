import SwiftUI

struct ArchivedWorktreeRowView: View {
  let worktree: Worktree
  let info: WorktreeInfoEntry?
  let onUnarchive: () -> Void
  let onDelete: () -> Void

  var body: some View {
    let pullRequest = info?.pullRequest
    let matchesWorktree =
      if let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == worktree.name
      } else {
        false
      }
    let displayPullRequest = matchesWorktree ? pullRequest : nil
    let pullRequestState = displayPullRequest?.state.uppercased()
    let pullRequestNumber = displayPullRequest?.number
    let pullRequestURL = displayPullRequest.flatMap { URL(string: $0.url) }
    let pullRequestTitle = displayPullRequest?.title
    let pullRequestChecks = displayPullRequest?.statusCheckRollup?.checks ?? []
    let pullRequestBadgeStyle = PullRequestBadgeStyle.style(
      state: pullRequestState,
      number: pullRequestNumber
    )
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    VStack(alignment: .leading) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text(worktree.name)
            .font(.headline)
          if !worktree.detail.isEmpty {
            Text(worktree.detail)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .monospaced()
          }
        }
        Spacer(minLength: 8)
        if let pullRequestBadgeStyle {
          PullRequestChecksPopoverButton(
            checks: pullRequestChecks,
            pullRequestURL: pullRequestURL,
            pullRequestTitle: pullRequestTitle
          ) {
            let breakdown = PullRequestCheckBreakdown(checks: pullRequestChecks)
            let showsChecksRing = breakdown.total > 0 && pullRequestState != "MERGED"
            HStack(spacing: 6) {
              if showsChecksRing {
                PullRequestChecksRingView(breakdown: breakdown)
              }
              PullRequestBadgeView(text: pullRequestBadgeStyle.text, color: pullRequestBadgeStyle.color)
            }
          }
        }
      }
      HStack {
        Button("Unarchive") {
          onUnarchive()
        }
        .help("Unarchive worktree")
        Button("Delete Worktree", role: .destructive) {
          onDelete()
        }
        .help("Delete Worktree (\(deleteShortcut))")
      }
    }
  }
}
