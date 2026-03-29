/// Identifies the kind of script that runs in a dedicated terminal tab
/// with exit-code tracking. Some kinds (archive, delete) block worktree
/// state transitions until the script completes. Adding a new case
/// requires handling in `AppFeature`'s `.blockingScriptCompleted` event router.
enum BlockingScriptKind: Hashable, Sendable, CaseIterable {
  case run
  case archive
  case delete

  var tabTitle: String {
    switch self {
    case .run: "Run Script"
    case .archive: "Archive Script"
    case .delete: "Delete Script"
    }
  }

  var tabIcon: String {
    switch self {
    case .run: "play.fill"
    case .archive: "archivebox.fill"
    case .delete: "trash.fill"
    }
  }

  var tabColor: TerminalTabTintColor {
    switch self {
    case .run: .green
    case .archive: .orange
    case .delete: .red
    }
  }
}
