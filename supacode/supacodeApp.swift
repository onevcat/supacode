//
//  supacodeApp.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import Foundation
import GhosttyKit
import SwiftUI

private enum GhosttyCLI {
  static let argv: [UnsafeMutablePointer<CChar>?] = {
    var args: [UnsafeMutablePointer<CChar>?] = []
    let executable = CommandLine.arguments.first ?? "supacode"
    args.append(strdup(executable))
    for shortcut in AppShortcuts.all {
      args.append(strdup("--keybind=\(shortcut.ghosttyKeybind)=unbind"))
    }
    args.append(nil)
    return args
  }()
}

@main
@MainActor
struct SupacodeApp: App {
  @State private var ghostty: GhosttyRuntime
  @State private var ghosttyShortcuts: GhosttyShortcutStore
  @State private var settings = SettingsModel()
  @State private var repositoryStore: RepositoryStore
  @State private var updateController: UpdateController

  @MainActor init() {
    if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("ghostty") {
      setenv("GHOSTTY_RESOURCES_DIR", resourceURL.path, 1)
    }
    GhosttyCLI.argv.withUnsafeBufferPointer { buffer in
      let argc = UInt(max(0, buffer.count - 1))
      let argv = UnsafeMutablePointer(mutating: buffer.baseAddress)
      if ghostty_init(argc, argv) != GHOSTTY_SUCCESS {
        preconditionFailure("ghostty_init failed")
      }
    }
    let runtime = GhosttyRuntime()
    _ghostty = State(initialValue: runtime)
    _ghosttyShortcuts = State(initialValue: GhosttyShortcutStore(runtime: runtime))
    let settingsModel = SettingsModel()
    _settings = State(initialValue: settingsModel)
    _repositoryStore = State(initialValue: makeRepositoryStore())
    _updateController = State(initialValue: UpdateController(settings: settingsModel))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(runtime: ghostty)
        .environment(settings)
        .environment(updateController)
        .environment(repositoryStore)
        .environment(ghosttyShortcuts)
        .preferredColorScheme(settings.preferredColorScheme)
    }
    .environment(ghosttyShortcuts)
    .commands {
      WorktreeCommands(repositoryStore: repositoryStore)
      SidebarCommands()
      TerminalCommands(ghosttyShortcuts: ghosttyShortcuts)
      UpdateCommands(updateController: updateController)
    }
    WindowGroup("Repo Settings", id: WindowIdentifiers.repoSettings, for: Repository.ID.self) { $repositoryID in
      if let repositoryID {
        RepositorySettingsView(repositoryRootURL: URL(fileURLWithPath: repositoryID))
      } else {
        Text("Select a repository to edit settings.")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding()
      }
    }
    .environment(ghosttyShortcuts)
    Settings {
      SettingsView()
        .environment(settings)
        .environment(updateController)
        .environment(repositoryStore)
        .environment(ghosttyShortcuts)
    }
    .environment(ghosttyShortcuts)
  }
}
