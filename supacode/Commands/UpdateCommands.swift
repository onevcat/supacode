import ComposableArchitecture
import SwiftUI

struct UpdateCommands: Commands {
  let store: StoreOf<UpdatesFeature>

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates...") {
        store.send(.checkForUpdates)
      }
      .keyboardShortcut(
        AppShortcuts.checkForUpdates.keyEquivalent,
        modifiers: AppShortcuts.checkForUpdates.modifiers
      )
      .help("Check for Updates (\(AppShortcuts.checkForUpdates.display))")
    }
  }
}
