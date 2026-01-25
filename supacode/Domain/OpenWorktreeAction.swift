import AppKit

enum OpenWorktreeAction: CaseIterable, Identifiable {
  case finder
  case cursor
  case ghostty
  case terminal
  case wezterm
  case xcode
  case zed

  var id: String { title }

  var title: String {
    switch self {
    case .finder: "Open Finder"
    case .cursor: "Cursor"
    case .ghostty: "Ghostty"
    case .terminal: "Terminal"
    case .wezterm: "WezTerm"
    case .xcode: "Xcode"
    case .zed: "Zed"
    }
  }

  var labelTitle: String {
    switch self {
    case .finder: "Finder"
    case .cursor, .ghostty, .terminal, .wezterm, .xcode, .zed: title
    }
  }

  var appIcon: NSImage? {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: appURL.path)
  }

  var settingsID: String {
    switch self {
    case .finder: "finder"
    case .cursor: "cursor"
    case .ghostty: "ghostty"
    case .terminal: "terminal"
    case .wezterm: "wezterm"
    case .xcode: "xcode"
    case .zed: "zed"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .finder: "com.apple.finder"
    case .cursor: "com.todesktop.230313mzl4w4u92"
    case .ghostty: "com.mitchellh.ghostty"
    case .terminal: "com.apple.Terminal"
    case .wezterm: "com.github.wez.wezterm"
    case .xcode: "com.apple.dt.Xcode"
    case .zed: "dev.zed.Zed"
    }
  }

  static func fromSettingsID(_ settingsID: String?) -> OpenWorktreeAction {
    switch settingsID {
    case OpenWorktreeAction.finder.settingsID: .finder
    case OpenWorktreeAction.cursor.settingsID: .cursor
    case OpenWorktreeAction.ghostty.settingsID: .ghostty
    case OpenWorktreeAction.terminal.settingsID: .terminal
    case OpenWorktreeAction.wezterm.settingsID: .wezterm
    case OpenWorktreeAction.xcode.settingsID: .xcode
    case OpenWorktreeAction.zed.settingsID: .zed
    default: .finder
    }
  }

  func perform(with worktree: Worktree, onError: @escaping (OpenActionError) -> Void) {
    switch self {
    case .finder:
      NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
    case .cursor, .ghostty, .terminal, .wezterm, .xcode, .zed:
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
