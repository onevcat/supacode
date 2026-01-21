import SwiftUI

struct TerminalCommands: Commands {
  @FocusedValue(\.newTerminalAction) private var newTerminalAction
  @FocusedValue(\.closeTabAction) private var closeTabAction

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("New Terminal") {
        newTerminalAction?()
      }
      .keyboardShortcut(
        AppShortcuts.newTerminal.keyEquivalent, modifiers: AppShortcuts.newTerminal.modifiers
      )
      .disabled(newTerminalAction == nil)
      Button("Close Tab") {
        closeTabAction?()
      }
      .keyboardShortcut(
        AppShortcuts.closeTab.keyEquivalent, modifiers: AppShortcuts.closeTab.modifiers
      )
      .disabled(closeTabAction == nil)
    }
  }
}

private struct NewTerminalActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var newTerminalAction: (() -> Void)? {
    get { self[NewTerminalActionKey.self] }
    set { self[NewTerminalActionKey.self] = newValue }
  }
}

private struct CloseTabActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var closeTabAction: (() -> Void)? {
    get { self[CloseTabActionKey.self] }
    set { self[CloseTabActionKey.self] = newValue }
  }
}
