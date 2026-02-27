import ComposableArchitecture
import SwiftUI

struct UpdateCommands: Commands {
  let store: StoreOf<UpdatesFeature>

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates...") {
        store.send(.checkForUpdates)
      }
      .help("Check for updates")
    }
  }
}
