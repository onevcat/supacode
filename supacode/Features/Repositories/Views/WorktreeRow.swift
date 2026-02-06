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
    let display = WorktreePullRequestDisplay(
      worktreeName: name,
      pullRequest: showsPullRequestInfo ? info?.pullRequest : nil
    )
    let displayAddedLines = info?.addedLines
    let displayRemovedLines = info?.removedLines
    let mergeReadiness = pullRequestMergeReadiness(for: display.pullRequest)
    let hasInfo = displayAddedLines != nil || displayRemovedLines != nil || mergeReadiness != nil
    let archiveShortcut = KeyboardShortcut(.delete, modifiers: .command).display
    let showsMergedArchiveAction = display.pullRequestState == "MERGED" && archiveAction != nil
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
          WorktreeRowInfoView(
            addedLines: displayAddedLines,
            removedLines: displayRemovedLines,
            mergeReadiness: mergeReadiness
          )
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
      if !showsMergedArchiveAction {
        WorktreePullRequestAccessoryView(display: display)
      }
      if let archiveAction, display.pullRequestState == "MERGED" {
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

  private func pullRequestMergeReadiness(
    for pullRequest: GithubPullRequest?
  ) -> PullRequestMergeReadiness? {
    guard let pullRequest, pullRequest.state.uppercased() == "OPEN" else {
      return nil
    }
    return PullRequestMergeReadiness(pullRequest: pullRequest)
  }
}

private struct WorktreeRowInfoView: View {
  let addedLines: Int?
  let removedLines: Int?
  let mergeReadiness: PullRequestMergeReadiness?

  var body: some View {
    HStack {
      if let addedLines, let removedLines {
        Text("+\(addedLines)")
          .foregroundStyle(.green)
        Text("-\(removedLines)")
          .foregroundStyle(.red)
      }
      if let mergeReadiness {
        if addedLines != nil && removedLines != nil {
          Text("•")
            .foregroundStyle(.secondary)
        }
        Text(mergeReadiness.label)
          .foregroundStyle(mergeReadiness.isBlocking ? .red : .green)
      }
    }
    .font(.caption)
    .lineLimit(1)
    .frame(minHeight: 14)
  }
}
