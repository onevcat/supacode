import SwiftUI

struct UpdateCommands: Commands {
  var updateController: UpdateController

  var body: some Commands {
    @Bindable var updateController = updateController
    CommandGroup(after: .appInfo) {
      Button("Check for Updates...") {
        updateController.checkForUpdates()
      }
      .keyboardShortcut(
        AppShortcuts.checkForUpdates.keyEquivalent,
        modifiers: AppShortcuts.checkForUpdates.modifiers
      )
      .help("Check for Updates (\(AppShortcuts.checkForUpdates.display))")
    }
  }
}
