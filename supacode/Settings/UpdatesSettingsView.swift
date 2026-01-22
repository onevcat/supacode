import SwiftUI

struct UpdatesSettingsView: View {
  @Environment(UpdateController.self) private var updateController

  var body: some View {
    @Bindable var updateController = updateController

    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section("Automatic Updates") {
          Toggle(
            "Check for updates automatically", isOn: $updateController.automaticallyChecksForUpdates
          )
          Toggle(
            "Download and install updates automatically",
            isOn: $updateController.automaticallyDownloadsUpdates
          )
          .disabled(!updateController.automaticallyChecksForUpdates)
        }
      }
      .formStyle(.grouped)

      HStack {
        Button("Check for Updates Now") {
          updateController.checkForUpdates()
        }
        .help("Check for Updates (\(AppShortcuts.checkForUpdates.display))")
        Spacer()
      }
      .padding(.top)
    }
    .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
