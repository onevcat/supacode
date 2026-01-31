import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeCommands: Commands {
  let store: StoreOf<AppFeature>
  @ObservedObject private var viewStore: ViewStore<AppFeature.State, AppFeature.Action>
  @FocusedValue(\.openSelectedWorktreeAction) private var openSelectedWorktreeAction
  @FocusedValue(\.confirmRemoveWorktreeAction) private var confirmRemoveWorktreeAction
  @FocusedValue(\.removeWorktreeAction) private var removeWorktreeAction
  @FocusedValue(\.runScriptAction) private var runScriptAction
  @FocusedValue(\.stopRunScriptAction) private var stopRunScriptAction

  init(store: StoreOf<AppFeature>) {
    self.store = store
    viewStore = ViewStore(store, observe: { $0 })
  }

  var body: some Commands {
    let repositories = viewStore.state.repositories
    let orderedRows = repositories.orderedWorktreeRows()
    let pullRequestURL = selectedPullRequestURL
    CommandMenu("Worktrees") {
      ForEach(worktreeShortcuts.indices, id: \.self) { index in
        let shortcut = worktreeShortcuts[index]
        worktreeShortcutButton(index: index, shortcut: shortcut, orderedRows: orderedRows)
      }
    }
    CommandGroup(replacing: .newItem) {
      Button("Open Repository...", systemImage: "folder") {
        store.send(.repositories(.setOpenPanelPresented(true)))
      }
      .keyboardShortcut(
        AppShortcuts.openRepository.keyEquivalent,
        modifiers: AppShortcuts.openRepository.modifiers
      )
      .help("Open Repository (\(AppShortcuts.openRepository.display))")
      Button("Open Worktree") {
        openSelectedWorktreeAction?()
      }
      .keyboardShortcut(
        AppShortcuts.openFinder.keyEquivalent,
        modifiers: AppShortcuts.openFinder.modifiers
      )
      .help("Open Worktree (\(AppShortcuts.openFinder.display))")
      .disabled(openSelectedWorktreeAction == nil)
      Button("Open Pull Request on GitHub") {
        if let pullRequestURL {
          NSWorkspace.shared.open(pullRequestURL)
        }
      }
      .keyboardShortcut(
        AppShortcuts.openPullRequest.keyEquivalent,
        modifiers: AppShortcuts.openPullRequest.modifiers
      )
      .help("Open Pull Request on GitHub (\(AppShortcuts.openPullRequest.display))")
      .disabled(pullRequestURL == nil)
      Button("New Worktree", systemImage: "plus") {
        store.send(.repositories(.createRandomWorktree))
      }
      .keyboardShortcut(
        AppShortcuts.newWorktree.keyEquivalent, modifiers: AppShortcuts.newWorktree.modifiers
      )
      .help("New Worktree (\(AppShortcuts.newWorktree.display))")
      .disabled(!repositories.canCreateWorktree)
      Button("Remove Worktree") {
        removeWorktreeAction?()
      }
      .keyboardShortcut(.delete, modifiers: .command)
      .help("Remove Worktree (⌘⌫)")
      .disabled(removeWorktreeAction == nil)
      Button("Confirm Remove Worktree") {
        confirmRemoveWorktreeAction?()
      }
      .keyboardShortcut(.return, modifiers: .command)
      .help("Confirm Remove Worktree (⌘↩)")
      .disabled(confirmRemoveWorktreeAction == nil)
      Button("Refresh Worktrees") {
        store.send(.repositories(.refreshWorktrees))
      }
      .keyboardShortcut(
        AppShortcuts.refreshWorktrees.keyEquivalent,
        modifiers: AppShortcuts.refreshWorktrees.modifiers
      )
      .help("Refresh Worktrees (\(AppShortcuts.refreshWorktrees.display))")
      Divider()
      Button("Run Script") {
        runScriptAction?()
      }
      .keyboardShortcut(
        AppShortcuts.runScript.keyEquivalent,
        modifiers: AppShortcuts.runScript.modifiers
      )
      .help("Run Script (\(AppShortcuts.runScript.display))")
      .disabled(runScriptAction == nil)
      Button("Stop Script") {
        stopRunScriptAction?()
      }
      .keyboardShortcut(
        AppShortcuts.stopRunScript.keyEquivalent,
        modifiers: AppShortcuts.stopRunScript.modifiers
      )
      .help("Stop Script (\(AppShortcuts.stopRunScript.display))")
      .disabled(stopRunScriptAction == nil)
    }
  }

  private var worktreeShortcuts: [AppShortcut] {
    AppShortcuts.worktreeSelection
  }

  private var selectedPullRequestURL: URL? {
    let repositories = viewStore.state.repositories
    guard let selectedWorktreeID = repositories.selectedWorktreeID else { return nil }
    let pullRequest = repositories.worktreeInfoByID[selectedWorktreeID]?.pullRequest
    return pullRequest.flatMap { URL(string: $0.url) }
  }

  private func worktreeShortcutButton(
    index: Int,
    shortcut: AppShortcut,
    orderedRows: [WorktreeRowModel]
  ) -> some View {
    let row = orderedRows.indices.contains(index) ? orderedRows[index] : nil
    let title = worktreeShortcutTitle(index: index, row: row)
    return Button(title) {
      guard let row else { return }
      store.send(.repositories(.selectWorktree(row.id)))
    }
    .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    .help("Switch to \(title) (\(shortcut.display))")
    .disabled(row == nil)
  }

  private func worktreeShortcutTitle(index: Int, row: WorktreeRowModel?) -> String {
    guard let row else { return "Worktree \(index + 1)" }
    let repositoryName = viewStore.state.repositories.repositoryName(for: row.repositoryID) ?? "Repository"
    return "\(repositoryName) — \(row.name)"
  }
}

private struct RemoveWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct OpenSelectedWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var openSelectedWorktreeAction: (() -> Void)? {
    get { self[OpenSelectedWorktreeActionKey.self] }
    set { self[OpenSelectedWorktreeActionKey.self] = newValue }
  }

  var confirmRemoveWorktreeAction: (() -> Void)? {
    get { self[ConfirmRemoveWorktreeActionKey.self] }
    set { self[ConfirmRemoveWorktreeActionKey.self] = newValue }
  }

  var removeWorktreeAction: (() -> Void)? {
    get { self[RemoveWorktreeActionKey.self] }
    set { self[RemoveWorktreeActionKey.self] = newValue }
  }

  var runScriptAction: (() -> Void)? {
    get { self[RunScriptActionKey.self] }
    set { self[RunScriptActionKey.self] = newValue }
  }

  var stopRunScriptAction: (() -> Void)? {
    get { self[StopRunScriptActionKey.self] }
    set { self[StopRunScriptActionKey.self] = newValue }
  }
}

private struct RunScriptActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct StopRunScriptActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct ConfirmRemoveWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}
