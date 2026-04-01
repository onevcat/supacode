import AppKit
import ComposableArchitecture
import SwiftUI

struct WorktreeDetailView: View {
  private struct ToolbarStateInput {
    let repositories: RepositoriesFeature.State
    let selectedWorktree: Worktree?
    let notificationGroups: [ToolbarNotificationRepositoryGroup]
    let unseenNotificationWorktreeCount: Int
    let openActionSelection: OpenWorktreeAction
    let showExtras: Bool
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool
    let customCommands: [UserCustomCommand]
  }

  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    detailBody(state: store.state)
  }

  private func detailBody(state: AppFeature.State) -> some View {
    let repositories = state.repositories
    let selectedRow = repositories.selectedRow(for: repositories.selectedWorktreeID)
    let selectedWorktree = repositories.worktree(for: repositories.selectedWorktreeID)
    let selectedTerminalWorktree = repositories.selectedTerminalWorktree
    let selectedWorktreeSummaries = selectedWorktreeSummaries(from: repositories)
    let showsMultiSelectionSummary = shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    let loadingInfo = loadingInfo(
      for: selectedRow,
      selectedWorktreeID: repositories.selectedWorktreeID,
      repositories: repositories
    )
    let hasActiveTerminalTarget =
      selectedTerminalWorktree != nil
      && loadingInfo == nil
      && !showsMultiSelectionSummary
    let openActionSelection = state.openActionSelection
    let runScriptEnabled = hasActiveTerminalTarget
    let runScriptIsRunning = selectedTerminalWorktree.flatMap { state.runScriptStatusByWorktreeID[$0.id] } == true
    let customCommands = state.selectedCustomCommands
    let notificationGroups = repositories.toolbarNotificationGroups(terminalManager: terminalManager)
    let unseenNotificationWorktreeCount = notificationGroups.reduce(0) { count, repository in
      count + repository.unseenWorktreeCount
    }
    let content = detailContent(
      repositories: repositories,
      loadingInfo: loadingInfo,
      selectedWorktree: selectedWorktree,
      selectedTerminalWorktree: selectedTerminalWorktree,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    .navigationTitle(repositories.isShowingCanvas ? "Canvas" : "")
    .toolbar(removing: repositories.isShowingCanvas ? nil : .title)
    .toolbar {
      if repositories.isShowingCanvas {
        ToolbarItem(placement: .primaryAction) {
          ToolbarNotificationsPopoverButton(
            groups: notificationGroups,
            unseenWorktreeCount: unseenNotificationWorktreeCount,
            onSelectNotification: selectToolbarNotification,
            onDismissAll: { dismissAllToolbarNotifications(in: notificationGroups) }
          )
        }
      } else if hasActiveTerminalTarget,
        let toolbarState = toolbarState(
          input: ToolbarStateInput(
            repositories: repositories,
            selectedWorktree: selectedWorktree,
            notificationGroups: notificationGroups,
            unseenNotificationWorktreeCount: unseenNotificationWorktreeCount,
            openActionSelection: openActionSelection,
            showExtras: commandKeyObserver.isPressed,
            runScriptEnabled: runScriptEnabled,
            runScriptIsRunning: runScriptIsRunning,
            customCommands: customCommands
          )
        )
      {
        WorktreeToolbarContent(
          toolbarState: toolbarState,
          onRenameBranch: { newBranch in
            guard let selectedWorktree else { return }
            store.send(.repositories(.requestRenameBranch(selectedWorktree.id, newBranch)))
          },
          onOpenWorktree: { action in
            store.send(.openWorktree(action))
          },
          onOpenActionSelectionChanged: { action in
            store.send(.openActionSelectionChanged(action))
          },
          onCopyPath: {
            guard let selectedTerminalWorktree else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedTerminalWorktree.workingDirectory.path, forType: .string)
          },
          onSelectNotification: selectToolbarNotification,
          onDismissAllNotifications: { dismissAllToolbarNotifications(in: notificationGroups) },
          onRunScript: { store.send(.runScript) },
          onStopRunScript: { store.send(.stopRunScript) },
          onRunCustomCommand: { index in
            store.send(.runCustomCommand(index))
          }
        )
      }
    }
    let actions = makeFocusedActions(
      repositories: repositories,
      hasActiveWorktree: hasActiveTerminalTarget,
      runScriptEnabled: runScriptEnabled,
      runScriptIsRunning: runScriptIsRunning
    )
    return applyFocusedActions(content: content, actions: actions)
  }

  private func toolbarState(input: ToolbarStateInput) -> WorktreeToolbarState? {
    guard
      let title = DetailToolbarTitle.forSelection(
        worktree: input.selectedWorktree,
        repository: input.repositories.selectedRepository
      )
    else {
      return nil
    }
    let pullRequest = input.selectedWorktree.flatMap { input.repositories.worktreeInfo(for: $0.id)?.pullRequest }
    let matchesBranch =
      if let selectedWorktree = input.selectedWorktree, let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == selectedWorktree.name
      } else {
        false
      }
    return WorktreeToolbarState(
      title: title,
      statusToast: input.repositories.statusToast,
      pullRequest: matchesBranch ? pullRequest : nil,
      notificationGroups: input.notificationGroups,
      unseenNotificationWorktreeCount: input.unseenNotificationWorktreeCount,
      openActionSelection: input.openActionSelection,
      showExtras: input.showExtras,
      runScriptEnabled: input.runScriptEnabled,
      runScriptIsRunning: input.runScriptIsRunning,
      customCommands: input.customCommands
    )
  }

  private func selectedWorktreeSummaries(
    from repositories: RepositoriesFeature.State
  ) -> [MultiSelectedWorktreeSummary] {
    repositories.sidebarSelectedWorktreeIDs
      .compactMap { worktreeID in
        repositories.selectedRow(for: worktreeID).map {
          MultiSelectedWorktreeSummary(
            id: $0.id,
            name: $0.name,
            repositoryName: repositories.repositoryName(for: $0.repositoryID)
          )
        }
      }
      .sorted { lhs, rhs in
        let lhsRepository = lhs.repositoryName ?? ""
        let rhsRepository = rhs.repositoryName ?? ""
        if lhsRepository == rhsRepository {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhsRepository.localizedCaseInsensitiveCompare(rhsRepository) == .orderedAscending
      }
  }

  private func shouldShowMultiSelectionSummary(
    repositories: RepositoriesFeature.State,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> Bool {
    !repositories.isShowingArchivedWorktrees
      && !repositories.isShowingCanvas
      && selectedWorktreeSummaries.count > 1
  }

  @ViewBuilder
  private func detailContent(
    repositories: RepositoriesFeature.State,
    loadingInfo: WorktreeLoadingInfo?,
    selectedWorktree: Worktree?,
    selectedTerminalWorktree: Worktree?,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> some View {
    if repositories.isShowingCanvas {
      CanvasView(
        terminalManager: terminalManager,
        onExitToTab: {
          store.send(.repositories(.toggleCanvas))
        })
    } else if repositories.isShowingArchivedWorktrees {
      ArchivedWorktreesDetailView(
        store: store.scope(state: \.repositories, action: \.repositories)
      )
    } else if shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    ) {
      MultiSelectedWorktreesDetailView(rows: selectedWorktreeSummaries)
    } else if let loadingInfo {
      WorktreeLoadingView(info: loadingInfo)
    } else if let selectedTerminalWorktree {
      let shouldRunSetupScript = repositories.pendingSetupScriptWorktreeIDs.contains(selectedTerminalWorktree.id)
      let shouldFocusTerminal = repositories.shouldFocusTerminal(for: selectedTerminalWorktree.id)
      WorktreeTerminalTabsView(
        worktree: selectedTerminalWorktree,
        manager: terminalManager,
        shouldRunSetupScript: shouldRunSetupScript,
        forceAutoFocus: shouldFocusTerminal,
        createTab: { store.send(.newTerminal) }
      )
      .id(selectedTerminalWorktree.id)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        if shouldFocusTerminal {
          store.send(.repositories(.consumeTerminalFocus(selectedTerminalWorktree.id)))
        }
      }
    } else if let selectedRepository = repositories.selectedRepository {
      RepositoryDetailView(repository: selectedRepository)
    } else {
      EmptyStateView(store: store.scope(state: \.repositories, action: \.repositories))
    }
  }

  private func applyFocusedActions<Content: View>(
    content: Content,
    actions: FocusedActions
  ) -> some View {
    content
      .focusedSceneValue(\.openSelectedWorktreeAction, actions.openSelectedWorktree)
      .focusedSceneValue(\.newTerminalAction, actions.newTerminal)
      .focusedValue(\.closeTabAction, actions.closeTab)
      .focusedValue(\.closeSurfaceAction, actions.closeSurface)
      .focusedSceneValue(\.resetFontSizeAction, actions.resetFontSize)
      .focusedSceneValue(\.increaseFontSizeAction, actions.increaseFontSize)
      .focusedSceneValue(\.decreaseFontSizeAction, actions.decreaseFontSize)
      .focusedSceneValue(\.startSearchAction, actions.startSearch)
      .focusedSceneValue(\.searchSelectionAction, actions.searchSelection)
      .focusedSceneValue(\.navigateSearchNextAction, actions.navigateSearchNext)
      .focusedSceneValue(\.navigateSearchPreviousAction, actions.navigateSearchPrevious)
      .focusedSceneValue(\.endSearchAction, actions.endSearch)
      .focusedSceneValue(\.selectPreviousTerminalTabAction, actions.selectPreviousTerminalTab)
      .focusedSceneValue(\.selectNextTerminalTabAction, actions.selectNextTerminalTab)
      .focusedSceneValue(\.selectPreviousTerminalPaneAction, actions.selectPreviousTerminalPane)
      .focusedSceneValue(\.selectNextTerminalPaneAction, actions.selectNextTerminalPane)
      .focusedSceneValue(\.selectTerminalPaneAboveAction, actions.selectTerminalPaneAbove)
      .focusedSceneValue(\.selectTerminalPaneBelowAction, actions.selectTerminalPaneBelow)
      .focusedSceneValue(\.selectTerminalPaneLeftAction, actions.selectTerminalPaneLeft)
      .focusedSceneValue(\.selectTerminalPaneRightAction, actions.selectTerminalPaneRight)
      .focusedSceneValue(\.runScriptAction, actions.runScript)
      .focusedSceneValue(\.stopRunScriptAction, actions.stopRunScript)
  }

  private func makeFocusedActions(
    repositories: RepositoriesFeature.State,
    hasActiveWorktree: Bool,
    runScriptEnabled: Bool,
    runScriptIsRunning: Bool
  ) -> FocusedActions {
    func action(_ appAction: AppFeature.Action) -> (() -> Void)? {
      hasActiveWorktree ? { store.send(appAction) } : nil
    }

    func canvasAction(_ perform: @escaping (WorktreeTerminalState) -> Bool) -> (() -> Void)? {
      guard repositories.isShowingCanvas else { return nil }
      return {
        guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
          let state = terminalManager.stateIfExists(for: worktreeID)
        else {
          return
        }
        _ = perform(state)
      }
    }

    func fontSizeAction(_ bindingAction: String) -> (() -> Void)? {
      if repositories.isShowingCanvas {
        return {
          guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
            let state = terminalManager.stateIfExists(for: worktreeID)
          else { return }
          _ = state.performBindingActionOnFocusedSurface(bindingAction)
          terminalManager.syncPreferredFontSize(from: worktreeID)
        }
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree else { return nil }
      return {
        guard let state = terminalManager.stateIfExists(for: selectedWorktree.id) else { return }
        _ = state.performBindingActionOnFocusedSurface(bindingAction)
        terminalManager.syncPreferredFontSize(from: selectedWorktree.id)
      }
    }

    func terminalBindingAction(_ bindingAction: String) -> (() -> Void)? {
      if let action = canvasAction({ $0.performBindingActionOnFocusedSurface(bindingAction) }) {
        return action
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree else { return nil }
      return {
        guard let state = terminalManager.stateIfExists(for: selectedWorktree.id) else { return }
        _ = state.performBindingActionOnFocusedSurface(bindingAction)
      }
    }

    return FocusedActions(
      openSelectedWorktree: action(.openSelectedWorktree),
      newTerminal: action(.newTerminal),
      closeTab: canvasAction { $0.closeFocusedTab() } ?? action(.closeTab),
      closeSurface: canvasAction { $0.closeFocusedSurface() } ?? action(.closeSurface),
      resetFontSize: fontSizeAction("reset_font_size"),
      increaseFontSize: fontSizeAction("increase_font_size:1"),
      decreaseFontSize: fontSizeAction("decrease_font_size:1"),
      startSearch: action(.startSearch),
      searchSelection: action(.searchSelection),
      navigateSearchNext: action(.navigateSearchNext),
      navigateSearchPrevious: action(.navigateSearchPrevious),
      endSearch: action(.endSearch),
      selectPreviousTerminalTab: terminalBindingAction("previous_tab"),
      selectNextTerminalTab: terminalBindingAction("next_tab"),
      selectPreviousTerminalPane: terminalBindingAction("goto_split:previous"),
      selectNextTerminalPane: terminalBindingAction("goto_split:next"),
      selectTerminalPaneAbove: terminalBindingAction("goto_split:up"),
      selectTerminalPaneBelow: terminalBindingAction("goto_split:down"),
      selectTerminalPaneLeft: terminalBindingAction("goto_split:left"),
      selectTerminalPaneRight: terminalBindingAction("goto_split:right"),
      runScript: runScriptEnabled ? { store.send(.runScript) } : nil,
      stopRunScript: runScriptIsRunning ? { store.send(.stopRunScript) } : nil
    )
  }

  private func selectToolbarNotification(
    _ worktreeID: Worktree.ID,
    _ notification: WorktreeTerminalNotification
  ) {
    store.send(.repositories(.selectWorktree(worktreeID)))
    if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
      _ = terminalState.focusSurface(id: notification.surfaceId)
    }
  }

  private func dismissAllToolbarNotifications(in groups: [ToolbarNotificationRepositoryGroup]) {
    for repositoryGroup in groups {
      for worktreeGroup in repositoryGroup.worktrees {
        terminalManager.stateIfExists(for: worktreeGroup.id)?.dismissAllNotifications()
      }
    }
  }

  private struct FocusedActions {
    let openSelectedWorktree: (() -> Void)?
    let newTerminal: (() -> Void)?
    let closeTab: (() -> Void)?
    let closeSurface: (() -> Void)?
    let resetFontSize: (() -> Void)?
    let increaseFontSize: (() -> Void)?
    let decreaseFontSize: (() -> Void)?
    let startSearch: (() -> Void)?
    let searchSelection: (() -> Void)?
    let navigateSearchNext: (() -> Void)?
    let navigateSearchPrevious: (() -> Void)?
    let endSearch: (() -> Void)?
    let selectPreviousTerminalTab: (() -> Void)?
    let selectNextTerminalTab: (() -> Void)?
    let selectPreviousTerminalPane: (() -> Void)?
    let selectNextTerminalPane: (() -> Void)?
    let selectTerminalPaneAbove: (() -> Void)?
    let selectTerminalPaneBelow: (() -> Void)?
    let selectTerminalPaneLeft: (() -> Void)?
    let selectTerminalPaneRight: (() -> Void)?
    let runScript: (() -> Void)?
    let stopRunScript: (() -> Void)?
  }

  fileprivate struct WorktreeToolbarState {
    let title: DetailToolbarTitle
    let statusToast: RepositoriesFeature.StatusToast?
    let pullRequest: GithubPullRequest?
    let notificationGroups: [ToolbarNotificationRepositoryGroup]
    let unseenNotificationWorktreeCount: Int
    let openActionSelection: OpenWorktreeAction
    let showExtras: Bool
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool
    let customCommands: [UserCustomCommand]
  }

  fileprivate struct WorktreeToolbarContent: ToolbarContent {
    let toolbarState: WorktreeToolbarState
    let onRenameBranch: (String) -> Void
    let onOpenWorktree: (OpenWorktreeAction) -> Void
    let onOpenActionSelectionChanged: (OpenWorktreeAction) -> Void
    let onCopyPath: () -> Void
    let onSelectNotification: (Worktree.ID, WorktreeTerminalNotification) -> Void
    let onDismissAllNotifications: () -> Void
    let onRunScript: () -> Void
    let onStopRunScript: () -> Void
    let onRunCustomCommand: (Int) -> Void
    @Environment(\.resolvedKeybindings) private var resolvedKeybindings

    var body: some ToolbarContent {
      ToolbarItem {
        WorktreeDetailTitleView(
          title: toolbarState.title,
          onSubmit: toolbarState.title.supportsRename ? onRenameBranch : nil
        )
      }

      ToolbarSpacer(.flexible)

      ToolbarItemGroup {
        ToolbarStatusView(
          toast: toolbarState.statusToast,
          pullRequest: toolbarState.pullRequest
        )
        .padding(.horizontal)
      }

      ToolbarSpacer(.fixed)
      ToolbarItemGroup {
        ToolbarNotificationsPopoverButton(
          groups: toolbarState.notificationGroups,
          unseenWorktreeCount: toolbarState.unseenNotificationWorktreeCount,
          onSelectNotification: onSelectNotification,
          onDismissAll: onDismissAllNotifications
        )
      }

      ToolbarSpacer(.flexible)

      ToolbarItemGroup {
        openMenu(
          openActionSelection: toolbarState.openActionSelection,
          showExtras: toolbarState.showExtras
        )
      }
      ToolbarSpacer(.fixed)
      commandToolbarItems

    }

    @ViewBuilder
    private func openMenu(openActionSelection: OpenWorktreeAction, showExtras: Bool) -> some View {
      let availableActions = OpenWorktreeAction.availableCases
      let resolvedOpenActionSelection = OpenWorktreeAction.availableSelection(openActionSelection)
      Button {
        onOpenWorktree(resolvedOpenActionSelection)
      } label: {
        OpenWorktreeActionMenuLabelView(
          action: resolvedOpenActionSelection,
          shortcutHint: showExtras ? shortcutDisplay(for: AppShortcuts.CommandID.openWorktree) : nil
        )
      }
      .help(openActionHelpText(for: resolvedOpenActionSelection, isDefault: true))

      Menu {
        ForEach(availableActions) { action in
          let isDefault = action == resolvedOpenActionSelection
          Button {
            onOpenActionSelectionChanged(action)
            onOpenWorktree(action)
          } label: {
            OpenWorktreeActionMenuLabelView(action: action, shortcutHint: nil)
          }
          .buttonStyle(.plain)
          .help(openActionHelpText(for: action, isDefault: isDefault))
        }
        Divider()
        Button("Copy Path") {
          onCopyPath()
        }
        .help("Copy path")
      } label: {
        Image(systemName: "chevron.down")
          .font(.caption2)
          .accessibilityLabel("Open in menu")
      }
      .imageScale(.small)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Open in...")

    }

    private func openActionHelpText(for action: OpenWorktreeAction, isDefault: Bool) -> String {
      guard isDefault else { return action.title }
      return AppShortcuts.helpText(
        title: action.title,
        commandID: AppShortcuts.CommandID.openWorktree,
        in: resolvedKeybindings
      )
    }

    @ToolbarContentBuilder
    private var commandToolbarItems: some ToolbarContent {
      if toolbarState.runScriptIsRunning || toolbarState.runScriptEnabled {
        ToolbarItem {
          RunScriptToolbarButton(
            isRunning: toolbarState.runScriptIsRunning,
            isEnabled: toolbarState.runScriptEnabled,
            runHelpText: AppShortcuts.helpText(
              title: "Run Script",
              commandID: AppShortcuts.CommandID.runScript,
              in: resolvedKeybindings
            ),
            stopHelpText: AppShortcuts.helpText(
              title: "Stop Script",
              commandID: AppShortcuts.CommandID.stopScript,
              in: resolvedKeybindings
            ),
            runShortcut: shortcutDisplay(for: AppShortcuts.CommandID.runScript),
            stopShortcut: shortcutDisplay(for: AppShortcuts.CommandID.stopScript),
            runAction: onRunScript,
            stopAction: onStopRunScript
          )
        }
      }

      let entries = customCommandEntries
      let inlineEntries = Array(entries.prefix(3))
      let overflowEntries = Array(entries.dropFirst(3))

      if !inlineEntries.isEmpty {
        ToolbarItemGroup {
          ForEach(inlineEntries, id: \.command.id) { entry in
            customCommandButton(entry.command, index: entry.index)
          }
        }
      }

      if !overflowEntries.isEmpty {
        ToolbarItem {
          CustomCommandOverflowButton(
            entries: overflowEntries,
            shortcutDisplay: customCommandShortcutDisplay(for:),
            onRunCustomCommand: onRunCustomCommand
          )
        }
      }
    }

    private var customCommandEntries: [(index: Int, command: UserCustomCommand)] {
      Array(toolbarState.customCommands.enumerated()).map { (index: $0.offset, command: $0.element) }
    }

    private func customCommandButton(_ command: UserCustomCommand, index: Int) -> some View {
      UserCustomCommandToolbarButton(
        title: command.resolvedTitle,
        systemImage: command.resolvedSystemImage,
        shortcut: customCommandShortcutDisplay(for: command),
        isEnabled: command.hasRunnableCommand,
        action: {
          onRunCustomCommand(index)
        }
      )
    }

    private func customCommandShortcutDisplay(for command: UserCustomCommand) -> String? {
      shortcutDisplay(for: LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id))
    }

    private func shortcutDisplay(for commandID: String) -> String? {
      AppShortcuts.display(for: commandID, in: resolvedKeybindings)
    }
  }

  private func loadingInfo(
    for selectedRow: WorktreeRowModel?,
    selectedWorktreeID: Worktree.ID?,
    repositories: RepositoriesFeature.State
  ) -> WorktreeLoadingInfo? {
    guard let selectedRow else { return nil }
    let repositoryName = repositories.repositoryName(for: selectedRow.repositoryID)
    if selectedRow.isDeleting {
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .removing,
        statusTitle: nil,
        statusDetail: nil,
        statusCommand: nil,
        statusLines: []
      )
    }
    if selectedRow.isArchiving {
      let progress = repositories.archiveScriptProgress(for: selectedWorktreeID)
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .archiving,
        statusTitle: progress?.titleText ?? selectedRow.name,
        statusDetail: progress?.detailText ?? selectedRow.detail,
        statusCommand: progress?.commandText,
        statusLines: progress?.outputLines ?? []
      )
    }
    if selectedRow.isPending {
      let pending = repositories.pendingWorktree(for: selectedWorktreeID)
      let progress = pending?.progress
      let displayName = progress?.worktreeName ?? selectedRow.name
      return WorktreeLoadingInfo(
        name: displayName,
        repositoryName: repositoryName,
        state: .creating,
        statusTitle: progress?.titleText ?? selectedRow.name,
        statusDetail: progress?.detailText ?? selectedRow.detail,
        statusCommand: progress?.commandText,
        statusLines: progress?.liveOutputLines ?? []
      )
    }
    return nil
  }
}

private struct MultiSelectedWorktreeSummary: Identifiable {
  let id: Worktree.ID
  let name: String
  let repositoryName: String?
}

private struct MultiSelectedWorktreesDetailView: View {
  let rows: [MultiSelectedWorktreeSummary]

  private let visibleRowsLimit = 8

  var body: some View {
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    VStack(alignment: .leading, spacing: 16) {
      Text("\(rows.count) worktrees selected")
        .font(.title3)
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(rows.prefix(visibleRowsLimit))) { row in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.name)
              .lineLimit(1)
            if let repositoryName = row.repositoryName {
              Text(repositoryName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .font(.body)
        }
        if rows.count > visibleRowsLimit {
          Text("+\(rows.count - visibleRowsLimit) more")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        Text("Available actions")
          .font(.headline)
        Text("Archive selected")
        Text("Delete selected (\(deleteShortcut))")
        Text("Right-click any selected worktree to apply actions to all selected worktrees.")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct RunScriptToolbarButton: View {
  let isRunning: Bool
  let isEnabled: Bool
  let runHelpText: String
  let stopHelpText: String
  let runShortcut: String?
  let stopShortcut: String?
  let runAction: () -> Void
  let stopAction: () -> Void
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    if isRunning {
      button(
        config: RunScriptButtonConfig(
          title: "Stop",
          systemImage: "stop.fill",
          helpText: stopHelpText,
          shortcut: stopShortcut,
          isEnabled: true,
          action: stopAction
        ))
    } else {
      button(
        config: RunScriptButtonConfig(
          title: "Run",
          systemImage: "play.fill",
          helpText: runHelpText,
          shortcut: runShortcut,
          isEnabled: isEnabled,
          action: runAction
        ))
    }
  }

  @ViewBuilder
  private func button(config: RunScriptButtonConfig) -> some View {
    Button {
      config.action()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: config.systemImage)
          .accessibilityHidden(true)
        Text(config.title)

        if commandKeyObserver.isPressed, let shortcut = config.shortcut {
          Text(shortcut)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.caption)
    .help(config.helpText)
    .disabled(!config.isEnabled)
  }

  private struct RunScriptButtonConfig {
    let title: String
    let systemImage: String
    let helpText: String
    let shortcut: String?
    let isEnabled: Bool
    let action: () -> Void
  }
}

private struct UserCustomCommandToolbarButton: View {
  let title: String
  let systemImage: String
  let shortcut: String?
  let isEnabled: Bool
  let action: () -> Void
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    Button {
      action()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
        Text(title)
        if commandKeyObserver.isPressed, let shortcut {
          Text(shortcut)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.caption)
    .help(helpText)
    .disabled(!isEnabled)
  }

  private var helpText: String {
    guard isEnabled else {
      return "\(title) (Set command script in Repository Settings)"
    }
    if let shortcut {
      return "\(title) (\(shortcut))"
    }
    return title
  }
}

private struct CustomCommandOverflowButton: View {
  let entries: [(index: Int, command: UserCustomCommand)]
  let shortcutDisplay: (UserCustomCommand) -> String?
  let onRunCustomCommand: (Int) -> Void

  @State private var isPresented = false
  private let maxVisibleRows = 10

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "chevron.down")
        .font(.caption2)
        .accessibilityLabel("More custom commands")
    }
    .help("More custom commands")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(entries, id: \.command.id) { entry in
            Button {
              isPresented = false
              onRunCustomCommand(entry.index)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: entry.command.resolvedSystemImage)
                  .foregroundStyle(.secondary)
                  .frame(width: 14)
                  .accessibilityHidden(true)
                Text(entry.command.resolvedTitle)
                  .lineLimit(1)
                Spacer(minLength: 0)
                if let shortcut = shortcutDisplay(entry.command) {
                  Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.command.hasRunnableCommand)
          }
        }
        .padding(8)
      }
      .frame(width: 320, height: popoverHeight)
    }
  }

  private var popoverHeight: CGFloat {
    let visibleRows = min(maxVisibleRows, max(entries.count, 1))
    return CGFloat(visibleRows) * 32 + 16
  }
}

@MainActor
private struct WorktreeToolbarPreview: View {
  private let toolbarState: WorktreeDetailView.WorktreeToolbarState
  private let commandKeyObserver: CommandKeyObserver

  init() {
    toolbarState = WorktreeDetailView.WorktreeToolbarState(
      title: DetailToolbarTitle(kind: .branch(name: "feature/toolbar-preview")),
      statusToast: nil,
      pullRequest: nil,
      notificationGroups: [],
      unseenNotificationWorktreeCount: 0,
      openActionSelection: .finder,
      showExtras: false,
      runScriptEnabled: true,
      runScriptIsRunning: false,
      customCommands: [
        UserCustomCommand(
          title: "Test",
          systemImage: "checkmark.circle.fill",
          command: "swift test",
          execution: .shellScript,
          shortcut: UserCustomShortcut(
            key: "u",
            modifiers: UserCustomShortcutModifiers()
          )
        ),
      ]
    )
    let observer = CommandKeyObserver()
    observer.isPressed = false
    commandKeyObserver = observer
  }

  var body: some View {
    NavigationStack {
      Text("Worktree Toolbar")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .toolbar {
      WorktreeDetailView.WorktreeToolbarContent(
        toolbarState: toolbarState,
        onRenameBranch: { _ in },
        onOpenWorktree: { _ in },
        onOpenActionSelectionChanged: { _ in },
        onCopyPath: {},
        onSelectNotification: { _, _ in },
        onDismissAllNotifications: {},
        onRunScript: {},
        onStopRunScript: {},
        onRunCustomCommand: { _ in }
      )
    }
    .environment(commandKeyObserver)
    .frame(width: 900, height: 160)
  }
}

#Preview("Worktree Toolbar") {
  WorktreeToolbarPreview()
}

@MainActor
private struct CanvasToolbarPreview: View {
  var body: some View {
    NavigationSplitView {
      List {
        Text("Sidebar Item 1")
        Text("Sidebar Item 2")
      }
      .navigationSplitViewColumnWidth(220)
    } detail: {
      Text("Canvas Content")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Canvas")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            ToolbarNotificationsPopoverButton(
              groups: [],
              unseenWorktreeCount: 0,
              onSelectNotification: { _, _ in },
              onDismissAll: {}
            )
          }
        }
    }
    .frame(width: 900, height: 300)
  }
}

#Preview("Canvas Toolbar") {
  CanvasToolbarPreview()
}
