import ComposableArchitecture
import SwiftUI

struct SidebarCommands: Commands {
  @Bindable var store: StoreOf<AppFeature>
  @FocusedValue(\.toggleLeftSidebarAction) private var toggleLeftSidebarAction

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
      Button("Toggle Left Sidebar") {
        toggleLeftSidebarAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.ID.toggleLeftSidebar)))
      .help("Toggle Left Sidebar (\(shortcutDisplay(for: AppShortcuts.ID.toggleLeftSidebar)))")
      .disabled(toggleLeftSidebarAction == nil)
      Divider()
      Button("Canvas") {
        store.send(.repositories(.toggleCanvas))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.ID.toggleCanvas)))
      .help("Canvas (\(shortcutDisplay(for: AppShortcuts.ID.toggleCanvas)))")
      Button("Show Diff") {
        let repos = store.repositories
        guard let worktreeID = repos.selectedWorktreeID,
          let worktree = repos.worktree(for: worktreeID)
        else { return }
        DiffWindowManager.shared.show(
          worktreeURL: worktree.workingDirectory,
          branchName: worktree.name,
        )
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.ID.showDiff)))
      .help("Show Diff (\(shortcutDisplay(for: AppShortcuts.ID.showDiff)))")
      .disabled(store.repositories.selectedWorktreeID == nil)
    }
  }

  private func keyboardShortcut(for commandID: String) -> KeyboardShortcut? {
    store.resolvedKeybindings.keyboardShortcut(for: commandID)
      ?? AppShortcuts.defaultShortcut(for: commandID)?.keyboardShortcut
  }

  private func shortcutDisplay(for commandID: String) -> String {
    store.resolvedKeybindings.display(for: commandID)
      ?? AppShortcuts.defaultShortcut(for: commandID)?.display
      ?? ""
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
