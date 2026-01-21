import SwiftUI

struct ChatSettingsView: View {
  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section {
          Text("No chat settings yet.")
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
