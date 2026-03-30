import SwiftUI

struct WindowCommands: Commands {
  let ghosttyShortcuts: GhosttyShortcutManager
  let resolvedKeybindings: ResolvedKeybindingMap
  @FocusedValue(\.closeSurfaceAction) private var closeSurfaceAction
  @FocusedValue(\.selectPreviousTerminalTabAction) private var selectPreviousTerminalTabAction
  @FocusedValue(\.selectNextTerminalTabAction) private var selectNextTerminalTabAction
  @FocusedValue(\.selectPreviousTerminalPaneAction) private var selectPreviousTerminalPaneAction
  @FocusedValue(\.selectNextTerminalPaneAction) private var selectNextTerminalPaneAction
  @FocusedValue(\.selectTerminalPaneAboveAction) private var selectTerminalPaneAboveAction
  @FocusedValue(\.selectTerminalPaneBelowAction) private var selectTerminalPaneBelowAction
  @FocusedValue(\.selectTerminalPaneLeftAction) private var selectTerminalPaneLeftAction
  @FocusedValue(\.selectTerminalPaneRightAction) private var selectTerminalPaneRightAction

  var body: some Commands {
    let closeSurfaceHotkey = ghosttyShortcuts.keyboardShortcut(for: "close_surface")
    let isCloseSurfaceOverlapping = closeSurfaceHotkey?.key == "w" && closeSurfaceHotkey?.modifiers == .command

    CommandGroup(replacing: .saveItem) {
      Button("Close Window", systemImage: "xmark") {
        NSApplication.shared.keyWindow?.performClose(nil)
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: !isCloseSurfaceOverlapping || closeSurfaceAction == nil ? .init("w") : nil
        )
      )
    }

    CommandGroup(replacing: .windowArrangement) {
      Button("Prowl") {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
          window.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
        }
      }
      .help("Show main window")
      Divider()

      Button("Select Previous Tab") {
        selectPreviousTerminalTabAction?()
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectPreviousTerminalTab)
        )
      )
      .disabled(selectPreviousTerminalTabAction == nil)

      Button("Select Next Tab") {
        selectNextTerminalTabAction?()
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectNextTerminalTab)
        )
      )
      .disabled(selectNextTerminalTabAction == nil)

      Divider()

      Button("Select Previous Pane") {
        selectPreviousTerminalPaneAction?()
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectPreviousTerminalPane)
        )
      )
      .disabled(selectPreviousTerminalPaneAction == nil)

      Button("Select Next Pane") {
        selectNextTerminalPaneAction?()
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectNextTerminalPane)
        )
      )
      .disabled(selectNextTerminalPaneAction == nil)

      Menu("Select Pane") {
        Button("Select Pane Above") {
          selectTerminalPaneAboveAction?()
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectTerminalPaneUp)
          )
        )
        .disabled(selectTerminalPaneAboveAction == nil)

        Button("Select Pane Below") {
          selectTerminalPaneBelowAction?()
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectTerminalPaneDown)
          )
        )
        .disabled(selectTerminalPaneBelowAction == nil)

        Button("Select Pane Left") {
          selectTerminalPaneLeftAction?()
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectTerminalPaneLeft)
          )
        )
        .disabled(selectTerminalPaneLeftAction == nil)

        Button("Select Pane Right") {
          selectTerminalPaneRightAction?()
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.selectTerminalPaneRight)
          )
        )
        .disabled(selectTerminalPaneRightAction == nil)
      }
    }
  }
}

struct KeyboardShortcutModifier: ViewModifier {
  let shortcut: KeyboardShortcut?

  func body(content: Content) -> some View {
    if let shortcut {
      content.keyboardShortcut(shortcut)
    } else {
      content
    }
  }
}

private struct SelectPreviousTerminalTabActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectPreviousTerminalTabAction: (() -> Void)? {
    get { self[SelectPreviousTerminalTabActionKey.self] }
    set { self[SelectPreviousTerminalTabActionKey.self] = newValue }
  }
}

private struct SelectNextTerminalTabActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectNextTerminalTabAction: (() -> Void)? {
    get { self[SelectNextTerminalTabActionKey.self] }
    set { self[SelectNextTerminalTabActionKey.self] = newValue }
  }
}

private struct SelectPreviousTerminalPaneActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectPreviousTerminalPaneAction: (() -> Void)? {
    get { self[SelectPreviousTerminalPaneActionKey.self] }
    set { self[SelectPreviousTerminalPaneActionKey.self] = newValue }
  }
}

private struct SelectNextTerminalPaneActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectNextTerminalPaneAction: (() -> Void)? {
    get { self[SelectNextTerminalPaneActionKey.self] }
    set { self[SelectNextTerminalPaneActionKey.self] = newValue }
  }
}

private struct SelectTerminalPaneAboveActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectTerminalPaneAboveAction: (() -> Void)? {
    get { self[SelectTerminalPaneAboveActionKey.self] }
    set { self[SelectTerminalPaneAboveActionKey.self] = newValue }
  }
}

private struct SelectTerminalPaneBelowActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectTerminalPaneBelowAction: (() -> Void)? {
    get { self[SelectTerminalPaneBelowActionKey.self] }
    set { self[SelectTerminalPaneBelowActionKey.self] = newValue }
  }
}

private struct SelectTerminalPaneLeftActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectTerminalPaneLeftAction: (() -> Void)? {
    get { self[SelectTerminalPaneLeftActionKey.self] }
    set { self[SelectTerminalPaneLeftActionKey.self] = newValue }
  }
}

private struct SelectTerminalPaneRightActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectTerminalPaneRightAction: (() -> Void)? {
    get { self[SelectTerminalPaneRightActionKey.self] }
    set { self[SelectTerminalPaneRightActionKey.self] = newValue }
  }
}
