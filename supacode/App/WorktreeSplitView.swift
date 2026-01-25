import ComposableArchitecture
import SwiftUI

struct WorktreeSplitView: View {
  let store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Binding var isInfoVisible: Bool

  var body: some View {
    if isInfoVisible {
      HSplitView {
        WorktreeDetailView(store: store, terminalManager: terminalManager)
        WorktreeInfoView(store: store.scope(state: \.worktreeInfo, action: \.worktreeInfo))
          .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
      }
    } else {
      WorktreeDetailView(store: store, terminalManager: terminalManager)
    }
  }
}
