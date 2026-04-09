import ComposableArchitecture
import SwiftUI

struct SidebarCommands: Commands {
  @Bindable var store: StoreOf<AppFeature>
  @FocusedValue(\.toggleLeftSidebarAction) private var toggleLeftSidebarAction
  @FocusedValue(\.revealInSidebarAction) private var revealInSidebarAction

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
      Button("Toggle Left Sidebar") {
        toggleLeftSidebarAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.toggleLeftSidebar)))
      .help(helpText(title: "Toggle Left Sidebar", commandID: AppShortcuts.CommandID.toggleLeftSidebar))
      .disabled(toggleLeftSidebarAction == nil)
      Button("Reveal in Sidebar") {
        revealInSidebarAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.revealInSidebar)))
      .help(helpText(title: "Reveal in Sidebar", commandID: AppShortcuts.CommandID.revealInSidebar))
      .disabled(revealInSidebarAction == nil)
      Divider()
      Button("Canvas") {
        store.send(.repositories(.toggleCanvas))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.toggleCanvas)))
      .help(helpText(title: "Canvas", commandID: AppShortcuts.CommandID.toggleCanvas))
      Button("Show Diff") {
        let repos = store.repositories
        guard let worktreeID = repos.selectedWorktreeID,
          let worktree = repos.worktree(for: worktreeID)
        else { return }
        DiffWindowManager.shared.show(
          worktreeURL: worktree.workingDirectory,
          branchName: worktree.name,
          resolvedKeybindings: store.resolvedKeybindings
        )
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.showDiff)))
      .help(helpText(title: "Show Diff", commandID: AppShortcuts.CommandID.showDiff))
      .disabled(store.repositories.selectedWorktreeID == nil)
    }
  }

  private func keyboardShortcut(for commandID: String) -> KeyboardShortcut? {
    store.resolvedKeybindings.keyboardShortcut(for: commandID)
  }

  private func helpText(title: String, commandID: String) -> String {
    if let shortcut = store.resolvedKeybindings.display(for: commandID) {
      return "\(title) (\(shortcut))"
    }
    return title
  }
}

private struct ToggleLeftSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct RevealInSidebarActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var toggleLeftSidebarAction: (() -> Void)? {
    get { self[ToggleLeftSidebarActionKey.self] }
    set { self[ToggleLeftSidebarActionKey.self] = newValue }
  }

  var revealInSidebarAction: (() -> Void)? {
    get { self[RevealInSidebarActionKey.self] }
    set { self[RevealInSidebarActionKey.self] = newValue }
  }
}
