import SwiftUI

struct NotificationPopoverView: View {
  let notifications: [WorktreeTerminalNotification]
  let onFocusSurface: (UUID) -> Void

  var body: some View {
    let count = notifications.count
    let countLabel = count == 1 ? "notification" : "notifications"
    ScrollView {
      VStack(alignment: .leading) {
        Text("Notifications")
          .font(.headline)
        Text("\(count) \(countLabel)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Divider()
        ForEach(notifications) { notification in
          Button {
            onFocusSurface(notification.surfaceId)
          } label: {
            HStack(alignment: .top) {
              Image(systemName: "bell")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
              Text(notification.content)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .font(.caption)
          .help("Focus pane")
        }
      }
      .padding()
    }
    .frame(minWidth: 260, maxWidth: 480, maxHeight: 400)
  }
}
