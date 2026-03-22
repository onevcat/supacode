import ComposableArchitecture
import SwiftUI

struct NotificationsSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var thresholdText = ""

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
            "Play notification sound",
            isOn: $store.notificationSoundEnabled
          )
          .help("Play a sound when a notification is received")
          Toggle(
            "System notifications",
            isOn: $store.systemNotificationsEnabled
          )
          .help("Show macOS system notifications")
          Toggle(
            "Move notified worktree to top",
            isOn: $store.moveNotifiedWorktreeToTop
          )
          .help("Bring the worktree to the top when the terminal receives a notification")
        }
        Section("Command Finished") {
          Toggle(
            "Notify when long-running commands finish",
            isOn: $store.commandFinishedNotificationEnabled
          )
          .help("Show a notification when a command exceeds the duration threshold")
          if store.commandFinishedNotificationEnabled {
            LabeledContent("Duration threshold") {
              HStack(spacing: 4) {
                TextField("", text: $thresholdText)
                  .frame(width: 40)
                  .multilineTextAlignment(.trailing)
                  .onSubmit {
                    store.send(.setCommandFinishedNotificationThreshold(thresholdText))
                  }
                  .onChange(of: store.commandFinishedNotificationThreshold) { _, newValue in
                    thresholdText = String(newValue)
                  }
                Text("seconds")
                  .foregroundStyle(.secondary)
              }
            }
            .help("Minimum command duration in seconds before a notification is shown")
            .onAppear {
              thresholdText = String(store.commandFinishedNotificationThreshold)
            }
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
