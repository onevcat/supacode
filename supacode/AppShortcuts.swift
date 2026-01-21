import SwiftUI

struct AppShortcut {
  let key: Character
  let modifiers: EventModifiers

  var keyEquivalent: KeyEquivalent {
    KeyEquivalent(key)
  }

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(keyEquivalent, modifiers: modifiers)
  }

  var ghosttyKeybind: String {
    let parts = ghosttyModifierParts + [String(key).lowercased()]
    return parts.joined(separator: "+")
  }

  var display: String {
    let parts = displayModifierParts + [String(key).uppercased()]
    return parts.joined()
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
  static let newTerminal = AppShortcut(key: "t", modifiers: .command)
  static let newWorktree = AppShortcut(key: "n", modifiers: .command)
  static let openFinder = AppShortcut(key: "o", modifiers: .command)
  static let copyPath = AppShortcut(key: "c", modifiers: [.command, .shift])
  static let openRepository = AppShortcut(key: "o", modifiers: [.command, .shift])
  static let toggleSidebar = AppShortcut(key: "[", modifiers: .command)
  static let closeTab = AppShortcut(key: "w", modifiers: .command)
  static let all: [AppShortcut] = [
    newTerminal,
    newWorktree,
    openFinder,
    copyPath,
    openRepository,
    toggleSidebar,
    closeTab,
  ]
}
