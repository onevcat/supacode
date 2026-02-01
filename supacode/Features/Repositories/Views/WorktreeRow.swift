import SwiftUI

struct WorktreeRow: View {
  let name: String
  let info: WorktreeInfoEntry?
  let isPinned: Bool
  let isMainWorktree: Bool
  let isLoading: Bool
  let taskStatus: WorktreeTaskStatus?
  let isRunScriptRunning: Bool
  let showsNotificationIndicator: Bool
  let shortcutHint: String?

  var body: some View {
    let showsSpinner = isLoading || taskStatus == .running
    let branchIconName = isMainWorktree ? "star.fill" : (isPinned ? "pin.fill" : "arrow.triangle.branch")
    let pullRequest = info?.pullRequest
    let matchesWorktree =
      if let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == name
      } else {
        false
      }
    let displayPullRequest = isMainWorktree ? nil : (matchesWorktree ? pullRequest : nil)
    let displayAddedLines = displayPullRequest == nil ? info?.addedLines : nil
    let displayRemovedLines = displayPullRequest == nil ? info?.removedLines : nil
    let hasInfo = displayAddedLines != nil || displayRemovedLines != nil
    let pullRequestState = displayPullRequest?.state.uppercased()
    let pullRequestNumber = displayPullRequest?.number
    let pullRequestURL = displayPullRequest.flatMap { URL(string: $0.url) }
    let pullRequestTitle = displayPullRequest?.title
    let pullRequestChecks = displayPullRequest?.statusCheckRollup?.checks ?? []
    let pullRequestBadgeStyle = PullRequestBadgeStyle.style(
      state: pullRequestState,
      number: pullRequestNumber
    )
    HStack(alignment: .center) {
      ZStack {
        if showsNotificationIndicator {
          Image(systemName: "bell.fill")
            .font(.caption)
            .monospaced()
            .foregroundStyle(.orange)
            .opacity(showsSpinner ? 0 : 1)
            .help("Unread notifications")
            .accessibilityLabel("Unread notifications")
        } else {
          Image(systemName: branchIconName)
            .font(.caption)
            .monospaced()
            .foregroundStyle(.secondary)
            .opacity(showsSpinner ? 0 : 1)
            .accessibilityHidden(true)
        }
        if showsSpinner {
          ProgressView()
            .controlSize(.small)
        }
      }
      .frame(width: 16, height: 16)
      if hasInfo {
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .monospaced()
          WorktreeRowInfoView(addedLines: displayAddedLines, removedLines: displayRemovedLines)
        }
      } else {
        Text(name)
          .monospaced()
      }
      Spacer(minLength: 8)
      if isRunScriptRunning {
        Image(systemName: "play.fill")
          .font(.caption)
          .monospaced()
          .foregroundStyle(.green)
          .help("Run script active")
          .accessibilityLabel("Run script active")
      }
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
        .help("Show pull request checks")
      }
      if let shortcutHint {
        ShortcutHintView(text: shortcutHint, color: .secondary)
      }
    }
  }

}

private struct WorktreeRowInfoView: View {
  let addedLines: Int?
  let removedLines: Int?

  var body: some View {
    HStack {
      if let addedLines, let removedLines {
        HStack {
          Text("+\(addedLines)")
            .foregroundStyle(.green)
          Text("-\(removedLines)")
            .foregroundStyle(.red)
        }
      }
    }
    .font(.caption)
    .monospaced()
    .frame(minHeight: 14)
  }
}
