import Bonsplit
import SwiftUI

struct WorktreeTerminalTabsView: View {
  let worktree: Worktree
  let store: WorktreeTerminalStore
  @Environment(RepositoryStore.self) private var repositoryStore

  var body: some View {
    let state = store.state(for: worktree) {
      repositoryStore.consumeSetupScript(for: worktree.id)
    }
    ZStack(alignment: .topLeading) {
      BonsplitView(
        controller: state.controller,
        content: { tab, _ in
          TerminalSplitTreeView(tree: state.splitTree(for: tab.id)) { operation in
            state.performSplitOperation(operation, in: tab.id)
          }
        },
        emptyPane: { _ in
          EmptyTerminalPaneView(message: "No terminals open")
        }
      )
      .overlay(alignment: .topTrailing) {
        Button("New Terminal", systemImage: "plus") {
          store.createTab(in: worktree)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("New Terminal (\(AppShortcuts.newTerminal.display))")
        .frame(height: state.controller.configuration.appearance.tabBarHeight)
        .padding(.trailing)
      }
    }
    .onAppear {
      state.ensureInitialTab()
    }
  }
}
