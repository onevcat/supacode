import ComposableArchitecture
import SwiftUI

struct UpdatesSettingsView: View {
  @Bindable var settingsStore: StoreOf<SettingsFeature>
  let updatesStore: StoreOf<UpdatesFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section("Update Channel") {
          Picker("Channel", selection: $settingsStore.updateChannel) {
            Text("Stable").tag(UpdateChannel.stable)
            Text("Tip").tag(UpdateChannel.tip)
          }
        }
        Section {
          Toggle(
            "Check for updates automatically",
            isOn: $settingsStore.updatesAutomaticallyCheckForUpdates
          )
        } header: {
          Text("Automatic Updates")
        } footer: {
          Text(
            "When a new version is available, a small badge appears next to the notifications bell. "
              + "Click it to review and install the update."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)

      HStack {
        Button("Check for Updates Now") {
          updatesStore.send(.checkForUpdates)
        }
        .help("Check for updates now")
        Spacer()
      }
      .padding(.top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
