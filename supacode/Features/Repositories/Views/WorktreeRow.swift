import SwiftUI

struct WorktreeRow: View {
  let name: String
  let isPinned: Bool
  let isMainWorktree: Bool
  let isLoading: Bool
  let taskStatus: WorktreeTaskStatus?
  let shortcutHint: String?

  var body: some View {
    let showsSpinner = isLoading || taskStatus == .running
    let iconName = isMainWorktree ? "star.fill" : (isPinned ? "pin.fill" : "arrow.triangle.branch")
    HStack(alignment: .center) {
      ZStack {
        Image(systemName: iconName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .opacity(showsSpinner ? 0 : 1)
          .accessibilityHidden(true)
        if showsSpinner {
          ProgressView()
            .controlSize(.small)
        }
      }
      Text(name)
      Spacer(minLength: 8)
      if let shortcutHint {
        ShortcutHintView(text: shortcutHint, color: .secondary)
      }
    }
  }
}
