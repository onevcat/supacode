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
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .monospaced()
        WorktreeRowInfoView(info: info)
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
      if let shortcutHint {
        ShortcutHintView(text: shortcutHint, color: .secondary)
      }
    }
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
      if let info, let pullRequestNumber = info.pullRequestNumber {
        Text("PR: \(pullRequestNumber)")
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .monospaced()
    .frame(minHeight: 14)
  }
}
