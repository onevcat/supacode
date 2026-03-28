import ComposableArchitecture
import SwiftUI

struct UpdateCommands: Commands {
  let store: StoreOf<UpdatesFeature>
  let resolvedKeybindings: ResolvedKeybindingMap

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates...") {
        store.send(.checkForUpdates)
      }
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.CommandID.checkForUpdates)))
      .help(helpText(title: "Check for Updates", commandID: AppShortcuts.CommandID.checkForUpdates))
    }
  }

  private func keyboardShortcut(for commandID: String) -> KeyboardShortcut? {
    resolvedKeybindings.keyboardShortcut(for: commandID)
  }

  private func helpText(title: String, commandID: String) -> String {
    if let shortcut = resolvedKeybindings.display(for: commandID) {
      return "\(title) (\(shortcut))"
    }
    return title
  }
}
