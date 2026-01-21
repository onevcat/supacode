import SwiftUI

struct SidebarCommands: Commands {
  @FocusedValue(\.toggleSidebarAction) private var toggleSidebarAction

  var body: some Commands {
    CommandMenu("View") {
      Button("Collapse Sidebar") {
        toggleSidebarAction?()
      }
      .keyboardShortcut(
        AppShortcuts.toggleSidebar.keyEquivalent, modifiers: AppShortcuts.toggleSidebar.modifiers
      )
      .help("Collapse Sidebar (\(AppShortcuts.toggleSidebar.display))")
      .disabled(toggleSidebarAction == nil)
    }
  }
}

private struct ToggleSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var toggleSidebarAction: (() -> Void)? {
    get { self[ToggleSidebarActionKey.self] }
    set { self[ToggleSidebarActionKey.self] = newValue }
  }
}
