import ComposableArchitecture
import SwiftUI

struct EmptyStateView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    let shortcutDisplay = AppShortcuts.display(for: AppShortcuts.CommandID.openRepository, in: resolvedKeybindings)
    VStack {
      Image(systemName: "tray")
        .font(.title2)
        .accessibilityHidden(true)
      Text("Open a repository or folder")
        .font(.headline)
      Text(promptText(shortcutDisplay: shortcutDisplay))
      .font(.subheadline)
      .foregroundStyle(.secondary)
      Button("Open Repository...") {
        store.send(.setOpenPanelPresented(true))
      }
      .modifier(KeyboardShortcutModifier(
        shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.openRepository)
      ))
      .help(AppShortcuts.helpText(
        title: "Open Repository",
        commandID: AppShortcuts.CommandID.openRepository,
        in: resolvedKeybindings
      ))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .multilineTextAlignment(.center)
  }

  private func promptText(shortcutDisplay: String?) -> String {
    if let shortcutDisplay {
      return "Press \(shortcutDisplay) or click Open Repository to choose a folder."
    }
    return "Click Open Repository to choose a folder."
  }
}
