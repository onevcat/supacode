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
struct SupacodeApp: App {
  @State private var ghostty: GhosttyRuntime
  @State private var settings = SettingsModel()
  @State private var repositoryStore = RepositoryStore()
  @State private var updateController: UpdateController

  init() {
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
    _ghostty = State(initialValue: GhosttyRuntime())
    let settingsModel = SettingsModel()
    _settings = State(initialValue: settingsModel)
    _updateController = State(initialValue: UpdateController(settings: settingsModel))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(runtime: ghostty)
        .environment(settings)
        .environment(updateController)
        .preferredColorScheme(settings.preferredColorScheme)
    }
    .environment(repositoryStore)
    WindowGroup("Repo Settings", id: WindowIdentifiers.repoSettings, for: Repository.ID.self) { $repositoryID in
      if let repositoryID {
        RepositorySettingsView(repositoryRootURL: URL(fileURLWithPath: repositoryID))
      } else {
        Text("Select a repository to edit settings.")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .scenePadding()
      }
    }
    .environment(repositoryStore)
    .commands {
      OpenRepositoryCommands(repositoryStore: repositoryStore)
      WorktreeCommands(repositoryStore: repositoryStore)
      SidebarCommands()
      TerminalCommands()
      UpdateCommands(updateController: updateController)
    }
    Settings {
      SettingsView()
        .environment(settings)
        .environment(updateController)
    }
    .environment(repositoryStore)
  }
}
