import SwiftUI

struct WorktreeRow: View {
  let name: String
  let info: WorktreeInfoEntry?
  let showsPullRequestInfo: Bool
  let isPinned: Bool
  let isMainWorktree: Bool
  let isLoading: Bool
  let taskStatus: WorktreeTaskStatus?
  let isRunScriptRunning: Bool
  let showsNotificationIndicator: Bool
  let notifications: [WorktreeTerminalNotification]
  let onClearNotifications: (() -> Void)?
  let onFocusSurface: (UUID) -> Void
  let shortcutHint: String?
  let archiveAction: (() -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let showsSpinner = isLoading || taskStatus == .running
    let branchIconName = isMainWorktree ? "star.fill" : (isPinned ? "pin.fill" : "arrow.triangle.branch")
    let pullRequest = showsPullRequestInfo ? info?.pullRequest : nil
    let matchesWorktree =
      if let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == name
      } else {
        false
      }
    let displayPullRequest = matchesWorktree ? pullRequest : nil
    let displayAddedLines = info?.addedLines
    let displayRemovedLines = info?.removedLines
    let hasInfo = displayAddedLines != nil || displayRemovedLines != nil
    let pullRequestState = displayPullRequest?.state.uppercased()
    let pullRequestNumber = displayPullRequest?.number
    let pullRequestChecks = displayPullRequest?.statusCheckRollup?.checks ?? []
    let archiveShortcut = KeyboardShortcut(.delete, modifiers: .command).display
    let pullRequestBadgeStyle = PullRequestBadgeStyle.style(
      state: pullRequestState,
      number: pullRequestNumber
    )
    let showsMergedArchiveAction = pullRequestState == "MERGED" && archiveAction != nil
    let nameColor = colorScheme == .dark ? Color.white : Color.primary
    HStack(alignment: .center) {
      ZStack {
        if showsNotificationIndicator {
          NotificationPopoverButton(
            notifications: notifications,
            onClear: onClearNotifications,
            onFocusSurface: onFocusSurface
          ) {
            Image(systemName: "bell.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .accessibilityLabel("Unread notifications")
          }
          .opacity(showsSpinner ? 0 : 1)
        } else {
          Image(systemName: branchIconName)
            .font(.caption)
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
            .font(.body)
            .foregroundStyle(nameColor)
          WorktreeRowInfoView(addedLines: displayAddedLines, removedLines: displayRemovedLines)
        }
      } else {
        Text(name)
          .font(.body)
          .foregroundStyle(nameColor)
      }
      Spacer(minLength: 8)
      if isRunScriptRunning {
        Image(systemName: "play.fill")
          .font(.caption)
          .foregroundStyle(.green)
          .help("Run script active")
          .accessibilityLabel("Run script active")
      }
      if let pullRequestBadgeStyle, let displayPullRequest, !showsMergedArchiveAction {
        PullRequestChecksPopoverButton(
          pullRequest: displayPullRequest
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
      if let archiveAction, pullRequestState == "MERGED" {
        Button {
          archiveAction()
        } label: {
          Image(systemName: "archivebox")
            .accessibilityLabel("Archive worktree")
        }
        .buttonStyle(.plain)
        .help("Archive Worktree (\(archiveShortcut))")
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
    .frame(minHeight: 14)
  }
}
