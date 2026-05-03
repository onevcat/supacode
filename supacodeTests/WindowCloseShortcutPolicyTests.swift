import SwiftUI
import Testing

@testable import supacode

struct WindowCloseShortcutPolicyTests {
  @Test func closeWindowDoesNotClaimCommandWWhenCloseSurfaceUsesCommandW() {
    let shortcut = WindowCloseShortcutPolicy.closeWindowShortcut(
      closeSurfaceShortcut: KeyboardShortcut("w"),
      closeTabShortcut: nil,
      hasTerminalCloseTarget: true
    )

    #expect(shortcut == nil)
  }

  @Test func closeWindowDoesNotClaimCommandWWhenCloseTabUsesCommandW() {
    let shortcut = WindowCloseShortcutPolicy.closeWindowShortcut(
      closeSurfaceShortcut: KeyboardShortcut("w", modifiers: [.option, .command]),
      closeTabShortcut: KeyboardShortcut("w"),
      hasTerminalCloseTarget: true
    )

    #expect(shortcut == nil)
  }

  @Test func closeWindowKeepsCommandWWhenTerminalCloseActionsUseDifferentShortcuts() {
    let shortcut = WindowCloseShortcutPolicy.closeWindowShortcut(
      closeSurfaceShortcut: KeyboardShortcut("w", modifiers: [.shift, .command]),
      closeTabShortcut: KeyboardShortcut("w", modifiers: [.option, .command]),
      hasTerminalCloseTarget: true
    )

    #expect(shortcut?.key == "w")
    #expect(shortcut?.modifiers == .command)
  }

  @Test func closeWindowKeepsCommandWWhenTerminalHasNoCloseTarget() {
    let shortcut = WindowCloseShortcutPolicy.closeWindowShortcut(
      closeSurfaceShortcut: KeyboardShortcut("w"),
      closeTabShortcut: KeyboardShortcut("w"),
      hasTerminalCloseTarget: false
    )

    #expect(shortcut?.key == "w")
    #expect(shortcut?.modifiers == .command)
  }
}
