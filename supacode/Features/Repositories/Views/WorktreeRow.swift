import SwiftUI

struct WorktreeRow: View {
  let name: String
  let info: WorktreeInfoEntry?
  let isPinned: Bool
  let isMainWorktree: Bool
  let isLoading: Bool
  let taskStatus: WorktreeTaskStatus?
  let showsNotificationIndicator: Bool
  let shortcutHint: String?

  var body: some View {
    let showsSpinner = isLoading || taskStatus == .running
    let branchIconName = isMainWorktree ? "star.fill" : (isPinned ? "pin.fill" : "arrow.triangle.branch")
    let hasInfo = info?.addedLines != nil || info?.removedLines != nil
    let pullRequestState = info?.pullRequest?.state.uppercased()
    let isMerged = pullRequestState == "MERGED"
    let isOpen = pullRequestState == "OPEN"
    let mergedColor = Color(red: 137.0 / 255.0, green: 87.0 / 255.0, blue: 229.0 / 255.0)
    let openColor = Color(red: 35.0 / 255.0, green: 134.0 / 255.0, blue: 54.0 / 255.0)
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
      if hasInfo {
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .monospaced()
          WorktreeRowInfoView(info: info)
        }
      } else {
        Text(name)
          .monospaced()
      }
      Spacer(minLength: 8)
      if taskStatus == .running {
        Image(systemName: "play.fill")
          .font(.caption)
          .monospaced()
          .foregroundStyle(.green)
          .help("Task running")
          .accessibilityLabel("Task running")
      }
      if isMerged {
        WorktreePullRequestBadge(text: "MERGED", color: mergedColor, help: "Pull request merged")
      } else if isOpen {
        WorktreePullRequestBadge(text: "OPEN", color: openColor, help: "Pull request open")
      }
      if let shortcutHint {
        ShortcutHintView(text: shortcutHint, color: .secondary)
      }
    }
  }
}

private struct WorktreePullRequestBadge: View {
  let text: String
  let color: Color
  let help: String

  var body: some View {
    Text(text)
      .font(.caption2)
      .monospaced()
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(color, lineWidth: 1)
      }
      .help(help)
      .accessibilityLabel(text)
  }
}

private struct WorktreeRowInfoView: View {
  let info: WorktreeInfoEntry?

  var body: some View {
    HStack {
      if let info, let addedLines = info.addedLines, let removedLines = info.removedLines {
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
