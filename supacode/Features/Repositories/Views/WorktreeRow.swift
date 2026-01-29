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
  @Environment(\.openURL) private var openURL

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
    let displayPullRequest = matchesWorktree ? pullRequest : nil
    let displayAddedLines = displayPullRequest?.additions ?? info?.addedLines
    let displayRemovedLines = displayPullRequest?.deletions ?? info?.removedLines
    let hasInfo = displayAddedLines != nil || displayRemovedLines != nil
    let pullRequestState = displayPullRequest?.state.uppercased()
    let pullRequestNumber = displayPullRequest?.number
    let pullRequestURL = displayPullRequest.flatMap { URL(string: $0.url) }
    let pullRequestBadgeStyle = PullRequestBadgeStyle.style(
      state: pullRequestState,
      number: pullRequestNumber
    )
    let pullRequestCheckBreakdown: PullRequestCheckBreakdown? = {
      guard let rollup = displayPullRequest?.statusCheckRollup else {
        return nil
      }
      guard !rollup.checks.isEmpty else {
        return nil
      }
      guard pullRequestState != "MERGED" else {
        return nil
      }
      return PullRequestCheckBreakdown(checks: rollup.checks)
    }()
    let pullRequestHelp = PullRequestBadgeStyle.helpText(state: pullRequestState, url: pullRequestURL)
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
        pullRequestBadge(
          text: pullRequestBadgeStyle.text,
          color: pullRequestBadgeStyle.color,
          help: pullRequestHelp,
          url: pullRequestURL,
          checkBreakdown: pullRequestCheckBreakdown
        )
      }
      if let shortcutHint {
        ShortcutHintView(text: shortcutHint, color: .secondary)
      }
    }
  }

  @ViewBuilder
  private func pullRequestBadge(
    text: String,
    color: Color,
    help: String,
    url: URL?,
    checkBreakdown: PullRequestCheckBreakdown?
  ) -> some View {
    if let url {
      Button {
        openURL(url)
      } label: {
        pullRequestBadgeContent(text: text, color: color, checkBreakdown: checkBreakdown)
      }
      .buttonStyle(.plain)
      .help(help)
    } else {
      pullRequestBadgeContent(text: text, color: color, checkBreakdown: checkBreakdown)
        .help(help)
    }
  }

  @ViewBuilder
  private func pullRequestBadgeContent(
    text: String,
    color: Color,
    checkBreakdown: PullRequestCheckBreakdown?
  ) -> some View {
    HStack(spacing: 6) {
      PullRequestBadgeView(text: text, color: color)
      if let checkBreakdown {
        PullRequestChecksRingView(breakdown: checkBreakdown)
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
