import ComposableArchitecture
import SwiftUI

struct SidebarFooterView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack {
      Button("Add Repository", systemImage: "folder.badge.plus") {
        store.send(.setOpenPanelPresented(true))
      }
      .help("Add Repository (\(AppShortcuts.openRepository.display))")
      Spacer()
      Menu {
        Button("Submit GitHub issue", systemImage: "exclamationmark.bubble") {
          if let url = URL(string: "https://github.com/supabitapp/supacode-sh/issues/new") {
            openURL(url)
          }
        }
        .help("Submit GitHub issue")
      } label: {
        Label("Help", systemImage: "questionmark.circle")
      }
      .labelStyle(.iconOnly)
      .help("Help")
      Button("Settings", systemImage: "gearshape") {
        SettingsWindowManager.shared.show()
      }
      .labelStyle(.iconOnly)
      .help("Settings (\(AppShortcuts.openSettings.display))")
    }
    .buttonStyle(.plain)
    .font(.callout)
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial)
  }
}
