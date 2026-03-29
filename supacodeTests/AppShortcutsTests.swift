import CustomDump
import SwiftUI
import Testing

@testable import supacode

@MainActor
struct AppShortcutsTests {
  @Test func displaySymbolsMatchDisplay() {
    let shortcuts: [AppShortcut] = [
      AppShortcuts.openSettings,
      AppShortcuts.newWorktree,
      AppShortcuts.copyPath,
    ]

    for shortcut in shortcuts {
      expectNoDifference(shortcut.displaySymbols.joined(), shortcut.display)
    }
  }

  @Test func worktreeSelectionUsesControlNumberShortcuts() {
    expectNoDifference(
      AppShortcuts.worktreeSelection.map(\.display),
      ["⌃1", "⌃2", "⌃3", "⌃4", "⌃5", "⌃6", "⌃7", "⌃8", "⌃9", "⌃0"]
    )

    for shortcut in AppShortcuts.worktreeSelection {
      #expect(shortcut.modifiers == .control)
    }
  }

  @Test func defaultGlobalShortcutTableMatchesPlan() {
    expectNoDifference(
      [
        "openSettings=\(AppShortcuts.openSettings.display)",
        "toggleLeftSidebar=\(AppShortcuts.toggleLeftSidebar.display)",
        "runScript=\(AppShortcuts.runScript.display)",
        "stopRunScript=\(AppShortcuts.stopRunScript.display)",
        "checkForUpdates=\(AppShortcuts.checkForUpdates.display)",
        "showDiff=\(AppShortcuts.showDiff.display)",
        "openFinder=\(AppShortcuts.openFinder.display)",
        "openRepository=\(AppShortcuts.openRepository.display)",
      ],
      [
        "openSettings=⌘,",
        "toggleLeftSidebar=⌘⌃S",
        "runScript=⌘R",
        "stopRunScript=⌘.",
        "checkForUpdates=⌘⇧U",
        "showDiff=⌘⇧Y",
        "openFinder=⌘O",
        "openRepository=⌘⇧O",
      ]
    )
  }

  @Test func systemFixedAndLocalInteractionShortcutsAreDefinedInRegistry() {
    let idToDisplay = Dictionary(uniqueKeysWithValues: AppShortcuts.bindings.map { ($0.id, $0.shortcut.display) })
    let idToScope = Dictionary(uniqueKeysWithValues: AppShortcuts.bindings.map { ($0.id, $0.scope) })

    expectNoDifference(
      idToDisplay["command_palette"],
      AppShortcuts.commandPalette.display
    )
    expectNoDifference(
      idToDisplay["quit_application"],
      AppShortcuts.quitApplication.display
    )
    expectNoDifference(
      idToDisplay["rename_branch"],
      AppShortcuts.renameBranch.display
    )
    expectNoDifference(
      idToDisplay["select_all_canvas_cards"],
      AppShortcuts.selectAllCanvasCards.display
    )

    #expect(idToScope["command_palette"] == .systemFixedAppAction)
    #expect(idToScope["quit_application"] == .systemFixedAppAction)
    #expect(idToScope["rename_branch"] == .localInteraction)
    #expect(idToScope["select_all_canvas_cards"] == .localInteraction)
  }

  @Test func tabSelectionGhosttyKeybindArgumentsMatchExpected() {
    expectNoDifference(
      AppShortcuts.tabSelectionGhosttyKeybindArguments,
      [
        "--keybind=ctrl+1=goto_tab:1",
        "--keybind=ctrl+digit_1=goto_tab:1",
        "--keybind=ctrl+2=goto_tab:2",
        "--keybind=ctrl+digit_2=goto_tab:2",
        "--keybind=ctrl+3=goto_tab:3",
        "--keybind=ctrl+digit_3=goto_tab:3",
        "--keybind=ctrl+4=goto_tab:4",
        "--keybind=ctrl+digit_4=goto_tab:4",
        "--keybind=ctrl+5=goto_tab:5",
        "--keybind=ctrl+digit_5=goto_tab:5",
        "--keybind=ctrl+6=goto_tab:6",
        "--keybind=ctrl+digit_6=goto_tab:6",
        "--keybind=ctrl+7=goto_tab:7",
        "--keybind=ctrl+digit_7=goto_tab:7",
        "--keybind=ctrl+8=goto_tab:8",
        "--keybind=ctrl+digit_8=goto_tab:8",
        "--keybind=ctrl+9=goto_tab:9",
        "--keybind=ctrl+digit_9=goto_tab:9",
        "--keybind=ctrl+0=goto_tab:10",
        "--keybind=ctrl+digit_0=goto_tab:10",
      ]
    )
  }

  @Test func userOverrideConflictsDetectsReservedAppShortcuts() {
    let commands = [
      UserCustomCommand(
        title: "Build",
        systemImage: "hammer",
        command: "swift build",
        execution: .shellScript,
        shortcut: UserCustomShortcut(
          key: "s",
          modifiers: UserCustomShortcutModifiers(command: true, control: true)
        )
      ),
      UserCustomCommand(
        title: "Deploy",
        systemImage: "rocket",
        command: "make release",
        execution: .shellScript,
        shortcut: UserCustomShortcut(
          key: "k",
          modifiers: UserCustomShortcutModifiers(command: true)
        )
      ),
    ]

    expectNoDifference(
      AppShortcuts.userOverrideConflicts(in: commands).map {
        "\($0.commandTitle)|\($0.commandShortcutDisplay)|\($0.appActionTitle)|\($0.appShortcutDisplay)"
      },
      [
        "Build|⌘⌃S|Toggle Left Sidebar|⌘⌃S"
      ]
    )
  }

  @Test func ghosttyCLIArgumentsKeepWorktreeUnbindsAndTabBinds() {
    let arguments = AppShortcuts.ghosttyCLIKeybindArguments

    for shortcut in AppShortcuts.worktreeSelection {
      #expect(arguments.contains(shortcut.ghosttyUnbindArgument))
    }

    for argument in AppShortcuts.tabSelectionGhosttyKeybindArguments {
      #expect(arguments.contains(argument))
    }

    for argument in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"].map({ "--keybind=ctrl+digit_\($0)=unbind" }) {
      #expect(arguments.contains(argument) == false)
    }

    for argument in [
      "--keybind=super+[=unbind",
      "--keybind=super+]=unbind",
      "--keybind=super+shift+[=unbind",
      "--keybind=super+shift+]=unbind",
      "--keybind=super+d=unbind",
      "--keybind=super+shift+d=unbind",
    ] {
      #expect(arguments.contains(argument) == false)
    }
  }
}
