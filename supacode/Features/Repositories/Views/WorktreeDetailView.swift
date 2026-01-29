import ComposableArchitecture
import SwiftUI

struct WorktreeDetailView: View {
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
    let loadingInfo = loadingInfo(for: selectedRow, repositories: repositories)
    let hasActiveWorktree = selectedWorktree != nil && loadingInfo == nil
    let pullRequest = selectedWorktree.flatMap { repositories.worktreeInfoByID[$0.id]?.pullRequest }
    let openActionSelection = state.openActionSelection
    let runScriptEnabled =
      hasActiveWorktree
      && !state.selectedRunScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let runScriptIsRunning = selectedWorktree.flatMap { state.runScriptStatusByWorktreeID[$0.id] } == true
    let navigationTitle =
      hasActiveWorktree
      ? ""
      : (selectedWorktree?.name ?? loadingInfo?.name ?? "Supacode")
    let content = Group {
      if let loadingInfo {
        WorktreeLoadingView(info: loadingInfo)
      } else if let selectedWorktree {
        let shouldRunSetupScript = repositories.pendingSetupScriptWorktreeIDs.contains(selectedWorktree.id)
        let shouldFocusTerminal = repositories.shouldFocusTerminal(for: selectedWorktree.id)
        WorktreeTerminalTabsView(
          worktree: selectedWorktree,
          manager: terminalManager,
          shouldRunSetupScript: shouldRunSetupScript,
          forceAutoFocus: shouldFocusTerminal,
          createTab: { store.send(.newTerminal) }
        )
        .id(selectedWorktree.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
          if shouldRunSetupScript {
            store.send(.repositories(.consumeSetupScript(selectedWorktree.id)))
          }
          if shouldFocusTerminal {
            store.send(.repositories(.consumeTerminalFocus(selectedWorktree.id)))
          }
        }
      } else {
        EmptyStateView(store: store.scope(state: \.repositories, action: \.repositories))
      }
    }
    .navigationTitle(navigationTitle)
    .toolbar {
      if hasActiveWorktree, let selectedWorktree {
        let toolbarState = WorktreeToolbarState(
          branchName: selectedWorktree.name,
          pullRequest: pullRequest,
          openActionSelection: openActionSelection,
          showExtras: commandKeyObserver.isPressed,
          runScriptEnabled: runScriptEnabled,
          runScriptIsRunning: runScriptIsRunning
        )
        worktreeToolbar(worktreeID: selectedWorktree.id, toolbarState: toolbarState)
      }
    }
    let actions = makeFocusedActions(
      hasActiveWorktree: hasActiveWorktree,
      runScriptEnabled: runScriptEnabled,
      runScriptIsRunning: runScriptIsRunning
    )
    return applyFocusedActions(content: content, actions: actions)
  }

  private func applyFocusedActions<Content: View>(
    content: Content,
    actions: FocusedActions
  ) -> some View {
    content
      .focusedSceneValue(\.openSelectedWorktreeAction, actions.openSelectedWorktree)
      .focusedSceneValue(\.newTerminalAction, actions.newTerminal)
      .focusedSceneValue(\.closeTabAction, actions.closeTab)
      .focusedSceneValue(\.closeSurfaceAction, actions.closeSurface)
      .focusedSceneValue(\.startSearchAction, actions.startSearch)
      .focusedSceneValue(\.searchSelectionAction, actions.searchSelection)
      .focusedSceneValue(\.navigateSearchNextAction, actions.navigateSearchNext)
      .focusedSceneValue(\.navigateSearchPreviousAction, actions.navigateSearchPrevious)
      .focusedSceneValue(\.endSearchAction, actions.endSearch)
      .focusedSceneValue(\.runScriptAction, actions.runScript)
      .focusedSceneValue(\.stopRunScriptAction, actions.stopRunScript)
  }

  private func makeFocusedActions(
    hasActiveWorktree: Bool,
    runScriptEnabled: Bool,
    runScriptIsRunning: Bool
  ) -> FocusedActions {
    func action(_ appAction: AppFeature.Action) -> (() -> Void)? {
      hasActiveWorktree ? { store.send(appAction) } : nil
    }
    return FocusedActions(
      openSelectedWorktree: action(.openSelectedWorktree),
      newTerminal: action(.newTerminal),
      closeTab: action(.closeTab),
      closeSurface: action(.closeSurface),
      startSearch: action(.startSearch),
      searchSelection: action(.searchSelection),
      navigateSearchNext: action(.navigateSearchNext),
      navigateSearchPrevious: action(.navigateSearchPrevious),
      endSearch: action(.endSearch),
      runScript: runScriptEnabled ? { store.send(.runScript) } : nil,
      stopRunScript: runScriptIsRunning ? { store.send(.stopRunScript) } : nil
    )
  }

  private struct FocusedActions {
    let openSelectedWorktree: (() -> Void)?
    let newTerminal: (() -> Void)?
    let closeTab: (() -> Void)?
    let closeSurface: (() -> Void)?
    let startSearch: (() -> Void)?
    let searchSelection: (() -> Void)?
    let navigateSearchNext: (() -> Void)?
    let navigateSearchPrevious: (() -> Void)?
    let endSearch: (() -> Void)?
    let runScript: (() -> Void)?
    let stopRunScript: (() -> Void)?
  }

  private struct WorktreeToolbarState {
    let branchName: String
    let pullRequest: GithubPullRequest?
    let openActionSelection: OpenWorktreeAction
    let showExtras: Bool
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool

    var runScriptHelpText: String {
      if runScriptEnabled {
        return "Run Script (\(AppShortcuts.runScript.display))"
      }
      return "Run Script (\(AppShortcuts.runScript.display)) — Set Run Script in repo settings"
    }

    var stopRunScriptHelpText: String {
      "Stop Script (\(AppShortcuts.stopRunScript.display))"
    }
  }

  private func loadingInfo(
    for selectedRow: WorktreeRowModel?,
    repositories: RepositoriesFeature.State
  ) -> WorktreeLoadingInfo? {
    guard let selectedRow else { return nil }
    let repositoryName = repositories.repositoryName(for: selectedRow.repositoryID)
    if selectedRow.isDeleting {
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .removing
      )
    }
    if selectedRow.isPending {
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .creating
      )
    }
    return nil
  }

  @ToolbarContentBuilder
  private func worktreeToolbar(
    worktreeID: Worktree.ID,
    toolbarState: WorktreeToolbarState
  ) -> some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      WorktreeDetailTitleView(
        branchName: toolbarState.branchName,
        onSubmit: { newBranch in
          store.send(.repositories(.requestRenameBranch(worktreeID, newBranch)))
        }
      )
    }
    ToolbarItem(placement: .principal) {
      HStack {
        if let model = PullRequestStatusModel(pullRequest: toolbarState.pullRequest) {
          PullRequestStatusButton(model: model).padding(.horizontal)
        } else {
          MiddleStatusView().padding(.horizontal)
        }
        Divider()
        RunScriptToolbarButton(
          isRunning: toolbarState.runScriptIsRunning,
          isEnabled: toolbarState.runScriptEnabled,
          runHelpText: toolbarState.runScriptHelpText,
          stopHelpText: toolbarState.stopRunScriptHelpText,
          runShortcut: AppShortcuts.runScript.display,
          stopShortcut: AppShortcuts.stopRunScript.display,
          runAction: { store.send(.runScript) },
          stopAction: { store.send(.stopRunScript) }
        )
      }
    }

    ToolbarItem(placement: .automatic) {
      openMenu(
        openActionSelection: toolbarState.openActionSelection,
        showExtras: toolbarState.showExtras
      )
    }
  }

  @ViewBuilder
  private func openMenu(openActionSelection: OpenWorktreeAction, showExtras: Bool) -> some View {
    let availableActions = OpenWorktreeAction.availableCases
    let resolvedOpenActionSelection = OpenWorktreeAction.availableSelection(openActionSelection)
    HStack(spacing: 0) {
      Button {
        store.send(.openWorktree(resolvedOpenActionSelection))
      } label: {
        OpenWorktreeActionMenuLabelView(
          action: resolvedOpenActionSelection,
          shortcutHint: showExtras ? AppShortcuts.openFinder.display : nil
        )
      }
      .buttonStyle(.borderless)
      .padding(8)
      .help(openActionHelpText(for: resolvedOpenActionSelection, isDefault: true))

      Divider()
        .frame(height: 16)

      Menu {
        ForEach(availableActions) { action in
          let isDefault = action == resolvedOpenActionSelection
          Button {
            store.send(.openActionSelectionChanged(action))
            store.send(.openWorktree(action))
          } label: {
            OpenWorktreeActionMenuLabelView(action: action, shortcutHint: nil)
          }
          .buttonStyle(.plain)
          .help(openActionHelpText(for: action, isDefault: isDefault))
        }
      } label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 8))
          .monospaced()
          .accessibilityLabel("Open in menu")
      }
      .buttonStyle(.borderless)
      .padding(8)
      .imageScale(.small)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Open in...")
    }
  }

  private func openActionHelpText(for action: OpenWorktreeAction, isDefault: Bool) -> String {
    isDefault
      ? "\(action.title) (\(AppShortcuts.openFinder.display))"
      : action.title
  }
}

private struct RunScriptToolbarButton: View {
  let isRunning: Bool
  let isEnabled: Bool
  let runHelpText: String
  let stopHelpText: String
  let runShortcut: String
  let stopShortcut: String
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
        if commandKeyObserver.isPressed {
          ShortcutHintView(text: config.shortcut, color: .secondary)
        } else {
          Text(config.title)
        }
      }
    }
    .font(.caption)
    .monospaced()
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .buttonStyle(.plain)
    .help(config.helpText)
    .disabled(!config.isEnabled)
  }

  private struct RunScriptButtonConfig {
    let title: String
    let systemImage: String
    let helpText: String
    let shortcut: String
    let isEnabled: Bool
    let action: () -> Void
  }
}

private struct WorktreeToolbarPreview: View {
  let branchName: String
  let prModel: PullRequestStatusModel?
  let openActionSelection: OpenWorktreeAction
  let showExtras: Bool
  let runScriptEnabled: Bool
  let runScriptIsRunning: Bool

  var body: some View {
    NavigationStack {
      Color.clear
        .frame(width: 800, height: 400)
        .navigationTitle("")
        .toolbar {
          worktreeToolbarContent
        }
    }
    .environment(CommandKeyObserver())
  }

  @ToolbarContentBuilder
  private var worktreeToolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      WorktreeDetailTitleView(branchName: branchName, onSubmit: { _ in })
    }
    ToolbarItem(placement: .principal) {
      if let prModel {
        PullRequestStatusButton(model: prModel).padding(.horizontal)
      } else {
        MiddleStatusView().padding(.horizontal)
      }
    }
    ToolbarItem(placement: .status) {
      RunScriptToolbarButton(
        isRunning: runScriptIsRunning,
        isEnabled: runScriptEnabled,
        runHelpText: "Run Script (⌘R)",
        stopHelpText: "Stop Script (⌘.)",
        runShortcut: "⌘R",
        stopShortcut: "⌘.",
        runAction: {},
        stopAction: {}
      )
    }
    ToolbarItem(placement: .automatic) {
      openMenuContent
    }
  }

  @ViewBuilder
  private var openMenuContent: some View {
    let availableActions = OpenWorktreeAction.availableCases
    let resolvedOpenActionSelection = OpenWorktreeAction.availableSelection(openActionSelection)
    HStack(spacing: 0) {
      Button {
      } label: {
        OpenWorktreeActionMenuLabelView(
          action: resolvedOpenActionSelection,
          shortcutHint: showExtras ? AppShortcuts.openFinder.display : nil
        )
      }
      .buttonStyle(.borderless)
      .padding(8)

      Divider()
        .frame(height: 16)

      Menu {
        ForEach(availableActions) { action in
          Button {
          } label: {
            OpenWorktreeActionMenuLabelView(action: action, shortcutHint: nil)
          }
          .buttonStyle(.plain)
        }
      } label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 8))
          .monospaced()
          .accessibilityLabel("Open in menu")
      }
      .buttonStyle(.borderless)
      .padding(8)
      .imageScale(.small)
      .menuIndicator(.hidden)
      .fixedSize()
    }
  }
}

#Preview("Toolbar - Running Script") {
  WorktreeToolbarPreview(
    branchName: "main",
    prModel: nil,
    openActionSelection: .cursor,
    showExtras: false,
    runScriptEnabled: true,
    runScriptIsRunning: true
  )
}
