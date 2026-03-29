import SwiftUI

struct AppShortcut: Equatable {
  let keyEquivalent: KeyEquivalent
  let modifiers: EventModifiers
  private let ghosttyKeyName: String

  init(key: Character, modifiers: EventModifiers) {
    self.keyEquivalent = KeyEquivalent(key)
    self.modifiers = modifiers
    self.ghosttyKeyName = String(key).lowercased()
  }

  init(keyEquivalent: KeyEquivalent, ghosttyKeyName: String, modifiers: EventModifiers) {
    self.keyEquivalent = keyEquivalent
    self.modifiers = modifiers
    self.ghosttyKeyName = ghosttyKeyName
  }

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(keyEquivalent, modifiers: modifiers)
  }

  var keyToken: String {
    ghosttyKeyName
  }

  var ghosttyKeybind: String {
    let parts = ghosttyModifierParts + [ghosttyKeyName]
    return parts.joined(separator: "+")
  }

  var ghosttyUnbindArgument: String {
    "--keybind=\(ghosttyKeybind)=unbind"
  }

  var display: String {
    let parts = displayModifierParts + [keyEquivalent.display]
    return parts.joined()
  }

  var displaySymbols: [String] {
    display.map { String($0) }
  }

  fileprivate var normalizedConflictKey: String? {
    guard ghosttyKeyName.count == 1 else { return nil }
    return ghosttyKeyName
  }

  private var ghosttyModifierParts: [String] {
    var parts: [String] = []
    if modifiers.contains(.control) { parts.append("ctrl") }
    if modifiers.contains(.option) { parts.append("alt") }
    if modifiers.contains(.shift) { parts.append("shift") }
    if modifiers.contains(.command) { parts.append("super") }
    return parts
  }

  private var displayModifierParts: [String] {
    var parts: [String] = []
    if modifiers.contains(.command) { parts.append("⌘") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.option) { parts.append("⌥") }
    if modifiers.contains(.control) { parts.append("⌃") }
    return parts
  }
}

enum AppShortcuts {
  enum Scope: String {
    case configurableAppAction
    case systemFixedAppAction
    case localInteraction
  }

  struct Binding: Equatable {
    let id: String
    let title: String
    let scope: Scope
    let shortcut: AppShortcut
  }

  struct CustomCommandOverrideConflict: Equatable {
    let commandTitle: String
    let commandShortcutDisplay: String
    let appActionTitle: String
    let appShortcutDisplay: String
  }

  private struct ReservedCustomCommandBinding {
    let actionTitle: String
    let shortcut: AppShortcut
  }

  private struct TabSelectionBinding {
    let unicode: String
    let physical: String
    let tabIndex: Int
  }

  private static let tabSelectionBindings: [TabSelectionBinding] = [
    TabSelectionBinding(unicode: "1", physical: "digit_1", tabIndex: 1),
    TabSelectionBinding(unicode: "2", physical: "digit_2", tabIndex: 2),
    TabSelectionBinding(unicode: "3", physical: "digit_3", tabIndex: 3),
    TabSelectionBinding(unicode: "4", physical: "digit_4", tabIndex: 4),
    TabSelectionBinding(unicode: "5", physical: "digit_5", tabIndex: 5),
    TabSelectionBinding(unicode: "6", physical: "digit_6", tabIndex: 6),
    TabSelectionBinding(unicode: "7", physical: "digit_7", tabIndex: 7),
    TabSelectionBinding(unicode: "8", physical: "digit_8", tabIndex: 8),
    TabSelectionBinding(unicode: "9", physical: "digit_9", tabIndex: 9),
    TabSelectionBinding(unicode: "0", physical: "digit_0", tabIndex: 10),
  ]

  static let newWorktree = AppShortcut(key: "n", modifiers: .command)
  static let commandPalette = AppShortcut(key: "p", modifiers: .command)
  static let quitApplication = AppShortcut(key: "q", modifiers: .command)
  static let openSettings = AppShortcut(key: ",", modifiers: .command)
  static let openFinder = AppShortcut(key: "o", modifiers: .command)
  static let copyPath = AppShortcut(key: "c", modifiers: [.command, .shift])
  static let openRepository = AppShortcut(key: "o", modifiers: [.command, .shift])
  static let openPullRequest = AppShortcut(key: "g", modifiers: [.command, .control])
  static let toggleLeftSidebar = AppShortcut(key: "s", modifiers: [.command, .control])
  static let refreshWorktrees = AppShortcut(key: "r", modifiers: [.command, .shift])
  static let runScript = AppShortcut(key: "r", modifiers: .command)
  static let stopRunScript = AppShortcut(key: ".", modifiers: .command)
  static let checkForUpdates = AppShortcut(key: "u", modifiers: [.command, .shift])
  static let showDiff = AppShortcut(key: "y", modifiers: [.command, .shift])
  static let toggleCanvas = AppShortcut(
    keyEquivalent: .return, ghosttyKeyName: "return", modifiers: [.command, .option]
  )
  static let archivedWorktrees = AppShortcut(key: "a", modifiers: [.command, .control])
  static let selectNextWorktree = AppShortcut(
    keyEquivalent: .downArrow, ghosttyKeyName: "arrow_down", modifiers: [.command, .control]
  )
  static let selectPreviousWorktree = AppShortcut(
    keyEquivalent: .upArrow, ghosttyKeyName: "arrow_up", modifiers: [.command, .control]
  )
  static let selectWorktree1 = AppShortcut(key: "1", modifiers: [.control])
  static let selectWorktree2 = AppShortcut(key: "2", modifiers: [.control])
  static let selectWorktree3 = AppShortcut(key: "3", modifiers: [.control])
  static let selectWorktree4 = AppShortcut(key: "4", modifiers: [.control])
  static let selectWorktree5 = AppShortcut(key: "5", modifiers: [.control])
  static let selectWorktree6 = AppShortcut(key: "6", modifiers: [.control])
  static let selectWorktree7 = AppShortcut(key: "7", modifiers: [.control])
  static let selectWorktree8 = AppShortcut(key: "8", modifiers: [.control])
  static let selectWorktree9 = AppShortcut(key: "9", modifiers: [.control])
  static let selectWorktree0 = AppShortcut(key: "0", modifiers: [.control])
  static let renameBranch = AppShortcut(key: "m", modifiers: [.command, .shift])
  static let selectAllCanvasCards = AppShortcut(key: "a", modifiers: [.command, .option])
  static let worktreeSelection: [AppShortcut] = [
    selectWorktree1,
    selectWorktree2,
    selectWorktree3,
    selectWorktree4,
    selectWorktree5,
    selectWorktree6,
    selectWorktree7,
    selectWorktree8,
    selectWorktree9,
    selectWorktree0,
  ]

  private static let reservedCustomCommandBindings: [ReservedCustomCommandBinding] = [
    .init(actionTitle: "Open Settings", shortcut: openSettings),
    .init(actionTitle: "Toggle Left Sidebar", shortcut: toggleLeftSidebar),
    .init(actionTitle: "Run Script", shortcut: runScript),
    .init(actionTitle: "Stop Script", shortcut: stopRunScript),
    .init(actionTitle: "Check for Updates", shortcut: checkForUpdates),
    .init(actionTitle: "Show Diff", shortcut: showDiff),
    .init(actionTitle: "Open Worktree", shortcut: openFinder),
    .init(actionTitle: "Open Repository", shortcut: openRepository),
  ]

  static let bindings: [Binding] = [
    .init(
      id: "new_worktree",
      title: "New Worktree",
      scope: .configurableAppAction,
      shortcut: newWorktree
    ),
    .init(
      id: "open_settings",
      title: "Open Settings",
      scope: .configurableAppAction,
      shortcut: openSettings
    ),
    .init(
      id: "open_worktree",
      title: "Open Worktree",
      scope: .configurableAppAction,
      shortcut: openFinder
    ),
    .init(
      id: "copy_path",
      title: "Copy Path",
      scope: .configurableAppAction,
      shortcut: copyPath
    ),
    .init(
      id: "open_repository",
      title: "Open Repository",
      scope: .configurableAppAction,
      shortcut: openRepository
    ),
    .init(
      id: "open_pull_request",
      title: "Open Pull Request",
      scope: .configurableAppAction,
      shortcut: openPullRequest
    ),
    .init(
      id: "toggle_left_sidebar",
      title: "Toggle Left Sidebar",
      scope: .configurableAppAction,
      shortcut: toggleLeftSidebar
    ),
    .init(
      id: "refresh_worktrees",
      title: "Refresh Worktrees",
      scope: .configurableAppAction,
      shortcut: refreshWorktrees
    ),
    .init(
      id: "run_script",
      title: "Run Script",
      scope: .configurableAppAction,
      shortcut: runScript
    ),
    .init(
      id: "stop_script",
      title: "Stop Script",
      scope: .configurableAppAction,
      shortcut: stopRunScript
    ),
    .init(
      id: "check_for_updates",
      title: "Check for Updates",
      scope: .configurableAppAction,
      shortcut: checkForUpdates
    ),
    .init(
      id: "show_diff",
      title: "Show Diff",
      scope: .configurableAppAction,
      shortcut: showDiff
    ),
    .init(
      id: "toggle_canvas",
      title: "Toggle Canvas",
      scope: .configurableAppAction,
      shortcut: toggleCanvas
    ),
    .init(
      id: "archived_worktrees",
      title: "Archived Worktrees",
      scope: .configurableAppAction,
      shortcut: archivedWorktrees
    ),
    .init(
      id: "select_next_worktree",
      title: "Select Next Worktree",
      scope: .configurableAppAction,
      shortcut: selectNextWorktree
    ),
    .init(
      id: "select_previous_worktree",
      title: "Select Previous Worktree",
      scope: .configurableAppAction,
      shortcut: selectPreviousWorktree
    ),
    .init(
      id: "select_worktree_1",
      title: "Select Worktree 1",
      scope: .configurableAppAction,
      shortcut: selectWorktree1
    ),
    .init(
      id: "select_worktree_2",
      title: "Select Worktree 2",
      scope: .configurableAppAction,
      shortcut: selectWorktree2
    ),
    .init(
      id: "select_worktree_3",
      title: "Select Worktree 3",
      scope: .configurableAppAction,
      shortcut: selectWorktree3
    ),
    .init(
      id: "select_worktree_4",
      title: "Select Worktree 4",
      scope: .configurableAppAction,
      shortcut: selectWorktree4
    ),
    .init(
      id: "select_worktree_5",
      title: "Select Worktree 5",
      scope: .configurableAppAction,
      shortcut: selectWorktree5
    ),
    .init(
      id: "select_worktree_6",
      title: "Select Worktree 6",
      scope: .configurableAppAction,
      shortcut: selectWorktree6
    ),
    .init(
      id: "select_worktree_7",
      title: "Select Worktree 7",
      scope: .configurableAppAction,
      shortcut: selectWorktree7
    ),
    .init(
      id: "select_worktree_8",
      title: "Select Worktree 8",
      scope: .configurableAppAction,
      shortcut: selectWorktree8
    ),
    .init(
      id: "select_worktree_9",
      title: "Select Worktree 9",
      scope: .configurableAppAction,
      shortcut: selectWorktree9
    ),
    .init(
      id: "select_worktree_0",
      title: "Select Worktree 0",
      scope: .configurableAppAction,
      shortcut: selectWorktree0
    ),
    .init(
      id: "command_palette",
      title: "Command Palette",
      scope: .systemFixedAppAction,
      shortcut: commandPalette
    ),
    .init(
      id: "quit_application",
      title: "Quit Application",
      scope: .systemFixedAppAction,
      shortcut: quitApplication
    ),
    .init(
      id: "rename_branch",
      title: "Rename Branch",
      scope: .localInteraction,
      shortcut: renameBranch
    ),
    .init(
      id: "select_all_canvas_cards",
      title: "Select All Canvas Cards",
      scope: .localInteraction,
      shortcut: selectAllCanvasCards
    ),
  ]

  static func userOverrideConflicts(
    in commands: [UserCustomCommand]
  ) -> [CustomCommandOverrideConflict] {
    var seen = Set<String>()
    return commands.compactMap { command in
      guard let shortcut = command.shortcut?.normalized(), shortcut.isValid else { return nil }
      guard let appBinding = matchingReservedBinding(for: shortcut) else { return nil }

      let signature =
        "\(command.id)|\(shortcut.display)|\(appBinding.actionTitle)|\(appBinding.shortcut.display)"
      guard seen.insert(signature).inserted else { return nil }

      return CustomCommandOverrideConflict(
        commandTitle: command.resolvedTitle,
        commandShortcutDisplay: shortcut.display,
        appActionTitle: appBinding.actionTitle,
        appShortcutDisplay: appBinding.shortcut.display
      )
    }
  }

  private static func matchingReservedBinding(
    for shortcut: UserCustomShortcut
  ) -> ReservedCustomCommandBinding? {
    guard let key = shortcut.normalizedConflictKey else { return nil }
    let modifiers = shortcut.modifiers.eventModifiers
    return reservedCustomCommandBindings.first {
      $0.shortcut.normalizedConflictKey == key && $0.shortcut.modifiers == modifiers
    }
  }

  static let tabSelectionGhosttyKeybindArguments: [String] = tabSelectionBindings.flatMap { binding in
    [
      "--keybind=ctrl+\(binding.unicode)=goto_tab:\(binding.tabIndex)",
      "--keybind=ctrl+\(binding.physical)=goto_tab:\(binding.tabIndex)",
    ]
  }

  static var ghosttyCLIKeybindArguments: [String] {
    all.map(\.ghosttyUnbindArgument) + tabSelectionGhosttyKeybindArguments
  }

  static let all: [AppShortcut] = [
    newWorktree,
    openSettings,
    openFinder,
    copyPath,
    openRepository,
    openPullRequest,
    toggleLeftSidebar,
    refreshWorktrees,
    runScript,
    stopRunScript,
    checkForUpdates,
    showDiff,
    toggleCanvas,
    archivedWorktrees,
    selectNextWorktree,
    selectPreviousWorktree,
    selectWorktree1,
    selectWorktree2,
    selectWorktree3,
    selectWorktree4,
    selectWorktree5,
    selectWorktree6,
    selectWorktree7,
    selectWorktree8,
    selectWorktree9,
    selectWorktree0,
  ]
}

extension UserCustomShortcut {
  fileprivate var normalizedConflictKey: String? {
    let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.count == 1 else { return nil }
    return normalized
  }
}
