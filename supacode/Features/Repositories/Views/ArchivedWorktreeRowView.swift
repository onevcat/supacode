import SwiftUI

struct ArchivedWorktreeRowView: View {
  let worktree: Worktree
  let info: WorktreeInfoEntry?
  let onUnarchive: () -> Void
  let onDelete: () -> Void

  var body: some View {
    let display = WorktreePullRequestDisplay(
      worktreeName: worktree.name,
      pullRequest: info?.pullRequest
    )
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(worktree.name)
          .font(.headline)
        Spacer(minLength: 12)
        HStack(spacing: 8) {
          Button("Unarchive", systemImage: "tray.and.arrow.up") {
            onUnarchive()
          }
          .help("Unarchive worktree")
          Button("Delete", systemImage: "trash", role: .destructive) {
            onDelete()
          }
          .help("Delete Worktree (\(deleteShortcut))")
        }
        .font(.callout)
        .buttonStyle(.borderless)
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if let createdAt = worktree.createdAt {
          Text("Created \(createdAt, style: .relative)")
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        WorktreePullRequestAccessoryView(display: display)
      }
      .font(.caption)
    }
  }
}
