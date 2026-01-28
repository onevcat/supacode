import AppKit

enum OpenWorktreeAction: CaseIterable, Identifiable {
  case alacritty
  case finder
  case cursor
  case ghostty
  case kitty
  case terminal
  case vscode
  case wezterm
  case xcode
  case zed

  var id: String { title }

  var title: String {
    switch self {
    case .finder: "Open Finder"
    case .alacritty: "Alacritty"
    case .cursor: "Cursor"
    case .ghostty: "Ghostty"
    case .kitty: "Kitty"
    case .terminal: "Terminal"
    case .vscode: "VS Code"
    case .wezterm: "WezTerm"
    case .xcode: "Xcode"
    case .zed: "Zed"
    }
  }

  var labelTitle: String {
    switch self {
    case .finder: "Finder"
    case .alacritty, .cursor, .ghostty, .kitty, .terminal, .vscode, .wezterm, .xcode, .zed: title
    }
  }

  var appIcon: NSImage? {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: appURL.path)
  }

  var isInstalled: Bool {
    switch self {
    case .finder:
      return true
    case .alacritty, .cursor, .ghostty, .kitty, .terminal, .vscode, .wezterm, .xcode, .zed:
      return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
  }

  var settingsID: String {
    switch self {
    case .finder: "finder"
    case .alacritty: "alacritty"
    case .cursor: "cursor"
    case .ghostty: "ghostty"
    case .kitty: "kitty"
    case .terminal: "terminal"
    case .vscode: "vscode"
    case .wezterm: "wezterm"
    case .xcode: "xcode"
    case .zed: "zed"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .finder: "com.apple.finder"
    case .alacritty: "org.alacritty"
    case .cursor: "com.todesktop.230313mzl4w4u92"
    case .ghostty: "com.mitchellh.ghostty"
    case .kitty: "net.kovidgoyal.kitty"
    case .terminal: "com.apple.Terminal"
    case .vscode: "com.microsoft.VSCode"
    case .wezterm: "com.github.wez.wezterm"
    case .xcode: "com.apple.dt.Xcode"
    case .zed: "dev.zed.Zed"
    }
  }

  nonisolated static let automaticSettingsID = "auto"

  static let editorPriority: [OpenWorktreeAction] = [.cursor, .zed, .vscode]
  static let terminalPriority: [OpenWorktreeAction] = [
    .ghostty,
    .wezterm,
    .alacritty,
    .kitty,
    .terminal,
  ]
  static let defaultPriority: [OpenWorktreeAction] = editorPriority + [.xcode, .finder] + terminalPriority
  static let menuOrder: [OpenWorktreeAction] = editorPriority + [.xcode] + [.finder] + terminalPriority

  static func fromSettingsID(_ settingsID: String?) -> OpenWorktreeAction {
    switch settingsID {
    case nil, automaticSettingsID:
      return preferredDefault()
    case OpenWorktreeAction.finder.settingsID:
      return .finder
    case OpenWorktreeAction.alacritty.settingsID:
      return .alacritty
    case OpenWorktreeAction.cursor.settingsID:
      return .cursor
    case OpenWorktreeAction.ghostty.settingsID:
      return .ghostty
    case OpenWorktreeAction.kitty.settingsID:
      return .kitty
    case OpenWorktreeAction.terminal.settingsID:
      return .terminal
    case OpenWorktreeAction.vscode.settingsID:
      return .vscode
    case OpenWorktreeAction.wezterm.settingsID:
      return .wezterm
    case OpenWorktreeAction.xcode.settingsID:
      return .xcode
    case OpenWorktreeAction.zed.settingsID:
      return .zed
    default:
      return preferredDefault()
    }
  }

  static var availableCases: [OpenWorktreeAction] {
    menuOrder.filter(\.isInstalled)
  }

  static func availableSelection(_ selection: OpenWorktreeAction) -> OpenWorktreeAction {
    selection.isInstalled ? selection : preferredDefault()
  }

  static func preferredDefault() -> OpenWorktreeAction {
    defaultPriority.first(where: \.isInstalled) ?? .finder
  }

  func perform(with worktree: Worktree, onError: @escaping (OpenActionError) -> Void) {
    switch self {
    case .finder:
      NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
    case .alacritty, .cursor, .ghostty, .kitty, .terminal, .vscode, .wezterm, .xcode, .zed:
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
