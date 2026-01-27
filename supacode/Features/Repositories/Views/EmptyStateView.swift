import ComposableArchitecture
import SwiftUI

struct EmptyStateView: View {
  let store: StoreOf<RepositoriesFeature>

  var body: some View {
    VStack {
      Image(systemName: "tray")
        .font(.title2)
        .monospaced()
        .accessibilityHidden(true)
      Text("Open a git repository")
        .font(.headline)
        .monospaced()
      Text(
        "Press \(AppShortcuts.openRepository.display) "
          + "or click Open Repository to choose a repository."
      )
      .font(.subheadline)
      .monospaced()
      .foregroundStyle(.secondary)
      Button("Open Repository...") {
        store.send(.setOpenPanelPresented(true))
      }
      .keyboardShortcut(
        AppShortcuts.openRepository.keyEquivalent,
        modifiers: AppShortcuts.openRepository.modifiers
      )
      .help("Open Repository (\(AppShortcuts.openRepository.display))")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .multilineTextAlignment(.center)
  }
}
