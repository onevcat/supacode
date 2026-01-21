import Bonsplit
import SwiftUI

struct WorktreeTerminalTabsView: View {
  let worktree: Worktree
  let store: WorktreeTerminalStore

  var body: some View {
    let state = store.state(for: worktree)
    ZStack(alignment: .topLeading) {
      BonsplitView(
        controller: state.controller,
        content: { tab, _ in
          GhosttyTerminalView(surfaceView: state.surfaceView(for: tab.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
