import SwiftUI

struct SidebarCommands: Commands {
  @FocusedValue(\.toggleLeftSidebarAction) private var toggleLeftSidebarAction

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
    }
  }
}

private struct ToggleLeftSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var toggleLeftSidebarAction: (() -> Void)? {
    get { self[ToggleLeftSidebarActionKey.self] }
    set { self[ToggleLeftSidebarActionKey.self] = newValue }
  }
}
