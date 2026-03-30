import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeCommands: Commands {
  @Bindable var store: StoreOf<AppFeature>
  @FocusedValue(\.openSelectedWorktreeAction) private var openSelectedWorktreeAction
  @FocusedValue(\.confirmWorktreeAction) private var confirmWorktreeAction
  @FocusedValue(\.archiveWorktreeAction) private var archiveWorktreeAction
  @FocusedValue(\.deleteWorktreeAction) private var deleteWorktreeAction
  @FocusedValue(\.runScriptAction) private var runScriptAction
  @FocusedValue(\.stopRunScriptAction) private var stopRunScriptAction
  @FocusedValue(\.visibleHotkeyWorktreeRows) private var visibleHotkeyWorktreeRows

  init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  var body: some Commands {
    let repositories = store.repositories
    let hasActiveWorktree = repositories.worktree(for: repositories.selectedWorktreeID) != nil
    let orderedRows = visibleHotkeyWorktreeRows ?? repositories.orderedWorktreeRows()
    let pullRequestURL = selectedPullRequestURL
    let githubIntegrationEnabled = store.settings.githubIntegrationEnabled
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    let customCommands = store.selectedCustomCommands
    CommandMenu("Worktrees") {
      Button("Select Next Worktree") {
        store.send(.repositories(.selectNextWorktree))
      }
      .modifier(
        KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.selectNextWorktree))
      )
      .help(helpText(title: "Select Next Worktree", commandID: AppShortcuts.CommandID.selectNextWorktree))
      .disabled(orderedRows.isEmpty)
      Button("Select Previous Worktree") {
        store.send(.repositories(.selectPreviousWorktree))
      }
      .modifier(
        KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.selectPreviousWorktree))
      )
      .help(helpText(title: "Select Previous Worktree", commandID: AppShortcuts.CommandID.selectPreviousWorktree))
      .disabled(orderedRows.isEmpty)
      Divider()
      ForEach(worktreeShortcutCommandIDs.indices, id: \.self) { index in
        let commandID = worktreeShortcutCommandIDs[index]
        worktreeShortcutButton(index: index, commandID: commandID, orderedRows: orderedRows)
      }
    }
    CommandGroup(replacing: .newItem) {
      if !customCommands.isEmpty {
        ForEach(Array(customCommands.enumerated()), id: \.element.id) { index, command in
          customCommandButton(
            index: index,
            command: command,
            hasActiveWorktree: hasActiveWorktree
          )
        }
        Divider()
      }
      Button("Open Repository...", systemImage: "folder") {
        store.send(.repositories(.setOpenPanelPresented(true)))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.openRepository)))
      .help(helpText(title: "Open Repository", commandID: AppShortcuts.CommandID.openRepository))
      Button("Open Worktree") {
        openSelectedWorktreeAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.openWorktree)))
      .help(helpText(title: "Open Worktree", commandID: AppShortcuts.CommandID.openWorktree))
      .disabled(openSelectedWorktreeAction == nil)
      Button("Open Pull Request on GitHub") {
        if let pullRequestURL {
          NSWorkspace.shared.open(pullRequestURL)
        }
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.openPullRequest)))
      .help(helpText(title: "Open Pull Request on GitHub", commandID: AppShortcuts.CommandID.openPullRequest))
      .disabled(pullRequestURL == nil || !githubIntegrationEnabled)
      Button("New Worktree", systemImage: "plus") {
        store.send(.repositories(.createRandomWorktree))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.newWorktree)))
      .help(helpText(title: "New Worktree", commandID: AppShortcuts.CommandID.newWorktree))
      .disabled(!repositories.canCreateWorktree)
      Button("Archived Worktrees") {
        store.send(.repositories(.selectArchivedWorktrees))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.archivedWorktrees)))
      .help(helpText(title: "Archived Worktrees", commandID: AppShortcuts.CommandID.archivedWorktrees))
      Button("Archive Worktree") {
        archiveWorktreeAction?()
      }
      .help("Archive Worktree")
      .disabled(archiveWorktreeAction == nil)
      Button("Delete Worktree") {
        deleteWorktreeAction?()
      }
      .keyboardShortcut(.delete, modifiers: [.command, .shift])
      .help("Delete Worktree (\(deleteShortcut))")
      .disabled(deleteWorktreeAction == nil)
      Button("Confirm Worktree Action") {
        confirmWorktreeAction?()
      }
      .keyboardShortcut(.return, modifiers: .command)
      .help("Confirm Worktree Action (⌘↩)")
      .disabled(confirmWorktreeAction == nil)
      Button("Refresh Worktrees") {
        store.send(.repositories(.refreshWorktrees))
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.refreshWorktrees)))
      .help(helpText(title: "Refresh Worktrees", commandID: AppShortcuts.CommandID.refreshWorktrees))
      Divider()
      Button("Run Script") {
        runScriptAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.runScript)))
      .help(helpText(title: "Run Script", commandID: AppShortcuts.CommandID.runScript))
      .disabled(runScriptAction == nil)
      Button("Stop Script") {
        stopRunScriptAction?()
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.stopScript)))
      .help(helpText(title: "Stop Script", commandID: AppShortcuts.CommandID.stopScript))
      .disabled(stopRunScriptAction == nil)
    }
  }

  private var worktreeShortcutCommandIDs: [String] {
    AppShortcuts.worktreeSelectionCommandIDs
  }

  private var selectedPullRequestURL: URL? {
    let repositories = store.repositories
    guard let selectedWorktreeID = repositories.selectedWorktreeID else { return nil }
    let pullRequest = repositories.worktreeInfoByID[selectedWorktreeID]?.pullRequest
    return pullRequest.flatMap { URL(string: $0.url) }
  }

  private func keyboardShortcut(for commandID: String) -> KeyboardShortcut? {
    store.resolvedKeybindings.keyboardShortcut(for: commandID)
  }

  private func shortcutDisplay(for commandID: String) -> String? {
    store.resolvedKeybindings.display(for: commandID)
  }

  private func helpText(title: String, commandID: String) -> String {
    if let shortcut = shortcutDisplay(for: commandID) {
      return "\(title) (\(shortcut))"
    }
    return title
  }

  private func customCommandID(for command: UserCustomCommand) -> String {
    LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id)
  }

  private func customCommandShortcut(for command: UserCustomCommand) -> KeyboardShortcut? {
    store.resolvedKeybindings.keyboardShortcut(for: customCommandID(for: command))
  }

  private func customCommandShortcutDisplay(for command: UserCustomCommand) -> String? {
    store.resolvedKeybindings.display(for: customCommandID(for: command))
  }

  private func worktreeShortcutButton(
    index: Int,
    commandID: String,
    orderedRows: [WorktreeRowModel]
  ) -> some View {
    let row = orderedRows.indices.contains(index) ? orderedRows[index] : nil
    let title = worktreeShortcutTitle(index: index, row: row)
    return Button(title) {
      guard let row else { return }
      store.send(.repositories(.selectWorktree(row.id)))
    }
    .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: commandID)))
    .help(
      {
        if let shortcut = shortcutDisplay(for: commandID) {
          return "Switch to \(title) (\(shortcut))"
        }
        return "Switch to \(title)"
      }()
    )
    .disabled(row == nil)
  }

  private func worktreeShortcutTitle(index: Int, row: WorktreeRowModel?) -> String {
    guard let row else { return "Worktree \(index + 1)" }
    let repositoryName = store.repositories.repositoryName(for: row.repositoryID) ?? "Repository"
    return "\(repositoryName) — \(row.name)"
  }

  @ViewBuilder
  private func customCommandButton(
    index: Int,
    command: UserCustomCommand,
    hasActiveWorktree: Bool
  ) -> some View {
    let title = command.resolvedTitle
    let helpText: String =
      if let shortcut = customCommandShortcutDisplay(for: command) {
        "\(title) (\(shortcut))"
      } else {
        title
      }
    Button(title, systemImage: command.resolvedSystemImage) {
      store.send(.runCustomCommand(index))
    }
    .modifier(KeyboardShortcutModifier(shortcut: customCommandShortcut(for: command)))
    .help(helpText)
    .disabled(!hasActiveWorktree)
  }
}

private struct ArchiveWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct OpenSelectedWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct DeleteWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct ConfirmWorktreeActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var openSelectedWorktreeAction: (() -> Void)? {
    get { self[OpenSelectedWorktreeActionKey.self] }
    set { self[OpenSelectedWorktreeActionKey.self] = newValue }
  }

  var confirmWorktreeAction: (() -> Void)? {
    get { self[ConfirmWorktreeActionKey.self] }
    set { self[ConfirmWorktreeActionKey.self] = newValue }
  }

  var archiveWorktreeAction: (() -> Void)? {
    get { self[ArchiveWorktreeActionKey.self] }
    set { self[ArchiveWorktreeActionKey.self] = newValue }
  }

  var deleteWorktreeAction: (() -> Void)? {
    get { self[DeleteWorktreeActionKey.self] }
    set { self[DeleteWorktreeActionKey.self] = newValue }
  }

  var runScriptAction: (() -> Void)? {
    get { self[RunScriptActionKey.self] }
    set { self[RunScriptActionKey.self] = newValue }
  }

  var stopRunScriptAction: (() -> Void)? {
    get { self[StopRunScriptActionKey.self] }
    set { self[StopRunScriptActionKey.self] = newValue }
  }

  var visibleHotkeyWorktreeRows: [WorktreeRowModel]? {
    get { self[VisibleHotkeyWorktreeRowsKey.self] }
    set { self[VisibleHotkeyWorktreeRowsKey.self] = newValue }
  }
}

private struct RunScriptActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct StopRunScriptActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct VisibleHotkeyWorktreeRowsKey: FocusedValueKey {
  typealias Value = [WorktreeRowModel]
}
