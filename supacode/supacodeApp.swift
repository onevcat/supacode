//
//  supacodeApp.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import GhosttyKit
import SwiftUI

@main
struct supacodeApp: App {
    @State private var ghostty: GhosttyRuntime
    @State private var settings = SettingsModel()
    @State private var repositoryStore = RepositoryStore()
    
    init() {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("ghostty") {
            setenv("GHOSTTY_RESOURCES_DIR", resourceURL.path, 1)
        }
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
                  preconditionFailure("ghostty_init failed")
              }
        _ghostty = State(initialValue: GhosttyRuntime())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(runtime: ghostty)
                .environment(settings)
                .preferredColorScheme(settings.preferredColorScheme)
        }
        .environment(repositoryStore)
        .commands {
            OpenRepositoryCommands(repositoryStore: repositoryStore)
        }
        Settings {
            SettingsView()
                .environment(settings)
        }
        .environment(repositoryStore)
    }
}
