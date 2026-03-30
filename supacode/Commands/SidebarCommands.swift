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
      .keyboardShortcut(
        AppShortcuts.toggleLeftSidebar.keyEquivalent, modifiers: AppShortcuts.toggleLeftSidebar.modifiers
      )
      .help("Toggle Left Sidebar (\(AppShortcuts.toggleLeftSidebar.display))")
      .disabled(toggleLeftSidebarAction == nil)
      Divider()
      Button("Canvas") {
        store.send(.repositories(.toggleCanvas))
      }
      .keyboardShortcut(
        AppShortcuts.toggleCanvas.keyEquivalent,
        modifiers: AppShortcuts.toggleCanvas.modifiers
      )
      .help("Canvas (\(AppShortcuts.toggleCanvas.display))")
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
      .keyboardShortcut(
        AppShortcuts.showDiff.keyEquivalent,
        modifiers: AppShortcuts.showDiff.modifiers
      )
      .help("Show Diff (\(AppShortcuts.showDiff.display))")
      .disabled(store.repositories.selectedWorktreeID == nil)
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
