import Observation
import SwiftUI

struct OpenRepositoryCommands: Commands {
    let repositoryStore: RepositoryStore

    var body: some Commands {
        @Bindable var repositoryStore = repositoryStore
        CommandGroup(after: .newItem) {
            Button("Open Repository...", systemImage: "folder") {
                repositoryStore.isOpenPanelPresented = true
            }
            .keyboardShortcut("o")
        }
    }
}
