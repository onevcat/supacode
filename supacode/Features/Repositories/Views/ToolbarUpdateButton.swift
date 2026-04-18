import SwiftUI

struct ToolbarUpdateButton: View {
  let availableVersion: String?
  let onCheckForUpdates: () -> Void

  private var tooltip: String {
    if let availableVersion, !availableVersion.isEmpty {
      return "Version \(availableVersion) is available. Click to review and install."
    }
    return "A new version is available. Click to review and install."
  }

  var body: some View {
    Button {
      onCheckForUpdates()
    } label: {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(Color("ProwlAccent"))
        .accessibilityHidden(true)
    }
    .help(tooltip)
    .accessibilityLabel("Install update")
  }
}
