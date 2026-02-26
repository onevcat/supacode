import ComposableArchitecture
import SwiftUI

struct NotificationsSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section("Notifications") {
          Toggle(
            "Show bell icon next to worktree",
            isOn: $store.inAppNotificationsEnabled
          )
          .help("Show bell icon next to worktree")
          Toggle(
            "Show Dock badge",
            isOn: $store.dockBadgeEnabled
          )
          .help("Show a badge on the Dock icon for unread notifications")
          Toggle(
            "Play in app notification sound",
            isOn: $store.notificationSoundEnabled
          )
          .help("Play a sound when a notification is received")
          Toggle(
            "System notification",
            isOn: $store.systemNotificationsEnabled
          )
          .help("Show macOS system notifications")
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
