import SwiftUI

struct AppearanceSettingsView: View {
  @Environment(SettingsModel.self) private var settings

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section("Appearance") {
          HStack {
            ForEach(AppearanceMode.allCases) { mode in
              AppearanceOptionCardView(
                mode: mode,
                isSelected: mode == settings.appearanceMode
              ) {
                settings.appearanceMode = mode
              }
            }
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
