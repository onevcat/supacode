import SwiftUI

struct SidebarCommands: Commands {
  @FocusedValue(\.toggleLeftSidebarAction) private var toggleLeftSidebarAction
  @FocusedValue(\.toggleRightSidebarAction) private var toggleRightSidebarAction

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
      Button("Toggle Left Sidebar") {
        toggleLeftSidebarAction?()
      }
      .keyboardShortcut(
        AppShortcuts.toggleLeftSidebar.keyEquivalent, modifiers: AppShortcuts.toggleLeftSidebar.modifiers
      )
      .help("Toggle Left Sidebar (\(AppShortcuts.toggleLeftSidebar.display))")
      .disabled(toggleLeftSidebarAction == nil)

      Button("Toggle Right Sidebar") {
        toggleRightSidebarAction?()
      }
      .keyboardShortcut(
        AppShortcuts.toggleRightSidebar.keyEquivalent, modifiers: AppShortcuts.toggleRightSidebar.modifiers
      )
      .help("Toggle Right Sidebar (\(AppShortcuts.toggleRightSidebar.display))")
      .disabled(toggleRightSidebarAction == nil)
    }
  }
}

private struct ToggleLeftSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct ToggleRightSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var toggleLeftSidebarAction: (() -> Void)? {
    get { self[ToggleLeftSidebarActionKey.self] }
    set { self[ToggleLeftSidebarActionKey.self] = newValue }
  }

  var toggleRightSidebarAction: (() -> Void)? {
    get { self[ToggleRightSidebarActionKey.self] }
    set { self[ToggleRightSidebarActionKey.self] = newValue }
  }
}
