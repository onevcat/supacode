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
      .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut(for: AppShortcuts.ID.checkForUpdates)))
      .help("Check for Updates (\(shortcutDisplay(for: AppShortcuts.ID.checkForUpdates)))")
    }
  }

  private func keyboardShortcut(for commandID: String) -> KeyboardShortcut? {
    resolvedKeybindings.keyboardShortcut(for: commandID)
      ?? AppShortcuts.defaultShortcut(for: commandID)?.keyboardShortcut
  }

  private func shortcutDisplay(for commandID: String) -> String {
    resolvedKeybindings.display(for: commandID)
      ?? AppShortcuts.defaultShortcut(for: commandID)?.display
      ?? ""
  }
}
