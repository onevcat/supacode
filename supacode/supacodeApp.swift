//
//  supacodeApp.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

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
      WorktreeCommands(repositoryStore: repositoryStore)
      SidebarCommands()
      TerminalCommands()
    }
    Settings {
      SettingsView()
        .environment(settings)
    }
    .environment(repositoryStore)
  }
}
