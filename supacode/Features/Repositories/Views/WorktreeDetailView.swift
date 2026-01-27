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
    let openActionSelection = state.openActionSelection
    let openSelectedWorktreeAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.openSelectedWorktree) }
      : nil
    let newTerminalAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.newTerminal) }
      : nil
    let closeTabAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.closeTab) }
      : nil
    let closeSurfaceAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.closeSurface) }
      : nil
    let startSearchAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.startSearch) }
      : nil
    let searchSelectionAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.searchSelection) }
      : nil
    let navigateSearchNextAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.navigateSearchNext) }
      : nil
    let navigateSearchPreviousAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.navigateSearchPrevious) }
      : nil
    let endSearchAction: (() -> Void)? = hasActiveWorktree
      ? { store.send(.endSearch) }
      : nil
    let navigationTitle = hasActiveWorktree
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
        worktreeToolbar(
          worktreeID: selectedWorktree.id,
          branchName: selectedWorktree.name,
          openActionSelection: openActionSelection,
          showExtras: commandKeyObserver.isPressed
        )
      }
    }
    let actions = FocusedActions(
      openSelectedWorktree: openSelectedWorktreeAction,
      newTerminal: newTerminalAction,
      closeTab: closeTabAction,
      closeSurface: closeSurfaceAction,
      startSearch: startSearchAction,
      searchSelection: searchSelectionAction,
      navigateSearchNext: navigateSearchNextAction,
      navigateSearchPrevious: navigateSearchPreviousAction,
      endSearch: endSearchAction
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
    branchName: String,
    openActionSelection: OpenWorktreeAction,
    showExtras: Bool
  ) -> some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      WorktreeDetailTitleView(
        branchName: branchName,
        onSubmit: { newBranch in
          store.send(.repositories(.requestRenameBranch(worktreeID, newBranch)))
        }
      )
    }
    ToolbarItem(placement: .principal) {
      XcodeStyleStatusView()
    }
    #if DEBUG
    ToolbarItem(placement: .automatic) {
      openMenu(openActionSelection: openActionSelection, showExtras: showExtras)
    }

    ToolbarItem(placement: .primaryAction) {
      Button("PR Button") { }.padding(.horizontal)
    }

    ToolbarItem(placement: .secondaryAction) {
      Button("secpond") { }.padding(.horizontal)
    }

    ToolbarItem(placement: .status) {
      Button("status") { }.padding(.horizontal)
    }
    #endif
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
