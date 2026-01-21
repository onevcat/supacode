import AppKit

enum OpenWorktreeAction: CaseIterable, Identifiable {
  case finder
  case cursor
  case zed
  case ghostty

  var id: String { title }

  var title: String {
    switch self {
    case .finder: "Open Finder"
    case .cursor: "Cursor"
    case .zed: "Zed"
    case .ghostty: "Ghostty"
    }
  }

  var appIcon: NSImage? {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: appURL.path)
  }

  var shortcut: AppShortcut? {
    switch self {
    case .finder: AppShortcuts.openFinder
    case .cursor, .zed, .ghostty: nil
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .finder: "com.apple.finder"
    case .cursor: "com.todesktop.230313mzl4w4u92"
    case .zed: "dev.zed.Zed"
    case .ghostty: "com.mitchellh.ghostty"
    }
  }

  var helpText: String {
    if let shortcut {
      return "\(title) (\(shortcut.display))"
    }
    return title
  }

  func perform(with worktree: Worktree, onError: @escaping (OpenActionError) -> Void) {
    switch self {
    case .finder:
      NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
    case .cursor, .zed, .ghostty:
      guard
        let appURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: bundleIdentifier
        )
      else {
        onError(
          OpenActionError(
            title: "\(title) not found",
            message: "Install \(title) to open this worktree."
          )
        )
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      NSWorkspace.shared.open(
        [worktree.workingDirectory],
        withApplicationAt: appURL,
        configuration: configuration
      ) { _, error in
        guard let error else { return }
        Task { @MainActor in
          onError(
            OpenActionError(
              title: "Unable to open in \(self.title)",
              message: error.localizedDescription
            )
          )
        }
      }
    }
  }
}
