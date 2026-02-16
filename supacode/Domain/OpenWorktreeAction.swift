import AppKit

enum OpenWorktreeAction: CaseIterable, Identifiable {
  enum MenuIcon {
    case app(NSImage)
    case symbol(String)
  }

  case alacritty
  case antigravity
  case editor
  case finder
  case cursor
  case githubDesktop
  case fork
  case gitkraken
  case gitup
  case ghostty
  case kitty
  case pycharm
  case smartgit
  case sourcetree
  case sublimeMerge
  case terminal
  case vscode
  case vscodeInsiders
  case warp
  case webstorm
  case wezterm
  case windsurf
  case xcode
  case zed

  var id: String { title }

  var title: String {
    switch self {
    case .finder: "Open Finder"
    case .editor: "$EDITOR"
    case .alacritty: "Alacritty"
    case .antigravity: "Antigravity"
    case .cursor: "Cursor"
    case .githubDesktop: "GitHub Desktop"
    case .gitkraken: "GitKraken"
    case .gitup: "GitUp"
    case .ghostty: "Ghostty"
    case .kitty: "Kitty"
    case .pycharm: "PyCharm"
    case .smartgit: "SmartGit"
    case .sourcetree: "Sourcetree"
    case .sublimeMerge: "Sublime Merge"
    case .terminal: "Terminal"
    case .vscode: "VS Code"
    case .vscodeInsiders: "VS Code Insiders"
    case .warp: "Warp"
    case .wezterm: "WezTerm"
    case .webstorm: "WebStorm"
    case .windsurf: "Windsurf"
    case .xcode: "Xcode"
    case .fork: "Fork"
    case .zed: "Zed"
    }
  }

  var labelTitle: String {
    switch self {
    case .finder: "Finder"
    case .editor: "$EDITOR"
    case .alacritty, .antigravity, .cursor, .fork, .githubDesktop, .gitkraken, .gitup, .ghostty,
      .kitty, .pycharm, .smartgit, .sourcetree, .sublimeMerge, .terminal, .vscode, .vscodeInsiders,
      .warp, .webstorm, .wezterm, .windsurf, .xcode, .zed:
      title
    }
  }

  var menuIcon: MenuIcon? {
    switch self {
    case .editor:
      return .symbol("apple.terminal")
    default:
      guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
      else { return nil }
      return .app(NSWorkspace.shared.icon(forFile: appURL.path))
    }
  }

  var isInstalled: Bool {
    switch self {
    case .finder, .editor:
      return true
    case .alacritty, .antigravity, .cursor, .fork, .githubDesktop, .gitkraken, .gitup, .ghostty,
      .kitty, .pycharm, .smartgit, .sourcetree, .sublimeMerge, .terminal, .vscode, .vscodeInsiders,
      .warp, .webstorm, .wezterm, .windsurf, .xcode, .zed:
      return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
  }

  var settingsID: String {
    switch self {
    case .finder: "finder"
    case .editor: "editor"
    case .alacritty: "alacritty"
    case .antigravity: "antigravity"
    case .cursor: "cursor"
    case .fork: "fork"
    case .githubDesktop: "github-desktop"
    case .gitkraken: "gitkraken"
    case .gitup: "gitup"
    case .ghostty: "ghostty"
    case .kitty: "kitty"
    case .pycharm: "pycharm"
    case .smartgit: "smartgit"
    case .sourcetree: "sourcetree"
    case .sublimeMerge: "sublime-merge"
    case .terminal: "terminal"
    case .vscode: "vscode"
    case .vscodeInsiders: "vscode-insiders"
    case .warp: "warp"
    case .webstorm: "webstorm"
    case .wezterm: "wezterm"
    case .windsurf: "windsurf"
    case .xcode: "xcode"
    case .zed: "zed"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .finder: "com.apple.finder"
    case .editor: ""
    case .alacritty: "org.alacritty"
    case .antigravity: "com.google.antigravity"
    case .cursor: "com.todesktop.230313mzl4w4u92"
    case .fork: "com.DanPristupov.Fork"
    case .githubDesktop: "com.github.GitHubClient"
    case .gitkraken: "com.axosoft.gitkraken"
    case .gitup: "co.gitup.mac"
    case .ghostty: "com.mitchellh.ghostty"
    case .kitty: "net.kovidgoyal.kitty"
    case .pycharm: "com.jetbrains.pycharm"
    case .smartgit: "com.syntevo.smartgit"
    case .sourcetree: "com.torusknot.SourceTreeNotMAS"
    case .sublimeMerge: "com.sublimemerge"
    case .terminal: "com.apple.Terminal"
    case .vscode: "com.microsoft.VSCode"
    case .vscodeInsiders: "com.microsoft.VSCodeInsiders"
    case .warp: "dev.warp.Warp-Stable"
    case .webstorm: "com.jetbrains.WebStorm"
    case .wezterm: "com.github.wez.wezterm"
    case .windsurf: "com.exafunction.windsurf"
    case .xcode: "com.apple.dt.Xcode"
    case .zed: "dev.zed.Zed"
    }
  }

  nonisolated static let automaticSettingsID = "auto"

  static let editorPriority: [OpenWorktreeAction] = [
    .cursor,
    .zed,
    .vscode,
    .windsurf,
    .vscodeInsiders,
    .webstorm,
    .pycharm,
    .antigravity,
  ]
  static let terminalPriority: [OpenWorktreeAction] = [
    .ghostty,
    .wezterm,
    .alacritty,
    .kitty,
    .warp,
    .terminal,
  ]
  static let gitClientPriority: [OpenWorktreeAction] = [
    .githubDesktop,
    .sourcetree,
    .fork,
    .gitkraken,
    .sublimeMerge,
    .smartgit,
    .gitup,
  ]
  static let defaultPriority: [OpenWorktreeAction] =
    editorPriority + [.xcode, .finder] + terminalPriority + gitClientPriority
  static let menuOrder: [OpenWorktreeAction] =
    editorPriority + [.xcode] + [.finder] + terminalPriority + gitClientPriority + [.editor]

  static func normalizedDefaultEditorID(_ settingsID: String?) -> String {
    guard let settingsID, settingsID != automaticSettingsID else {
      return automaticSettingsID
    }
    guard let action = allCases.first(where: { $0.settingsID == settingsID }),
      action.isInstalled
    else {
      return automaticSettingsID
    }
    return settingsID
  }

  static func fromSettingsID(
    _ settingsID: String?,
    defaultEditorID: String?
  ) -> OpenWorktreeAction {
    if let settingsID, settingsID != automaticSettingsID,
      let action = allCases.first(where: { $0.settingsID == settingsID })
    {
      return action
    }
    let normalizedDefaultEditorID = normalizedDefaultEditorID(defaultEditorID)
    if normalizedDefaultEditorID != automaticSettingsID,
      let action = allCases.first(where: { $0.settingsID == normalizedDefaultEditorID })
    {
      return action
    }
    return preferredDefault()
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
    case .editor:
      return
    case .finder:
      NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
    // Apps that require CLI arguments instead of Apple Events to open directories.
    case .webstorm, .pycharm:
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
      configuration.createsNewApplicationInstance = true
      configuration.arguments = [worktree.workingDirectory.path]
      NSWorkspace.shared.openApplication(
        at: appURL,
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
    case .alacritty, .antigravity, .cursor, .fork, .githubDesktop, .gitkraken, .gitup, .ghostty,
      .kitty, .smartgit, .sourcetree, .sublimeMerge, .terminal, .vscode, .vscodeInsiders, .warp,
      .wezterm, .windsurf, .xcode, .zed:
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
