import Observation
import SwiftUI

struct WorktreeCommands: Commands {
    let repositoryStore: RepositoryStore
    @FocusedValue(\.removeWorktreeAction) private var removeWorktreeAction

    var body: some Commands {
        @Bindable var repositoryStore = repositoryStore
        CommandGroup(replacing: .newItem) {
            Button("New Worktree", systemImage: "plus") {
                Task {
                    await repositoryStore.createRandomWorktree()
                }
            }
            .keyboardShortcut(AppShortcuts.newWorktree.keyEquivalent, modifiers: AppShortcuts.newWorktree.modifiers)
            .help("New Worktree (\(AppShortcuts.newWorktree.display))")
            .disabled(!repositoryStore.canCreateWorktree)
            Button("Remove Worktree") {
                removeWorktreeAction?()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Remove Worktree (⌘⌫)")
            .disabled(removeWorktreeAction == nil)
        }
    }
}

private struct RemoveWorktreeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var removeWorktreeAction: (() -> Void)? {
        get { self[RemoveWorktreeActionKey.self] }
        set { self[RemoveWorktreeActionKey.self] = newValue }
    }
}
