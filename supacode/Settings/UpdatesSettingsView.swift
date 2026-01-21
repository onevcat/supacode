import SwiftUI

struct UpdatesSettingsView: View {
  @State private var checkForUpdatesAutomatically = true
  @State private var downloadUpdatesAutomatically = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section("Automatic Updates") {
          Toggle("Check for updates automatically", isOn: $checkForUpdatesAutomatically)
          Toggle("Download and install updates automatically", isOn: $downloadUpdatesAutomatically)
        }
      }
      .formStyle(.grouped)

      HStack {
        Button("Check for Updates Now") {}
        Spacer()
      }
      .padding(.top)
    }
    .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
