import SwiftUI

struct WorktreeNotificationsListView: View {
  @Bindable var state: WorktreeTerminalState
  let worktreeName: String

  var body: some View {
    if state.notificationsEnabled, !state.notifications.isEmpty {
      VStack(alignment: .leading) {
        Text("Notifications")
          .font(.headline)
          .ghosttyMonospaced(.headline)
        ForEach(state.notifications) { notification in
          Button {
            _ = state.focusSurface(id: notification.surfaceId)
          } label: {
            Text("\(worktreeName) - \(notification.content)")
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .help("Focus pane")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
