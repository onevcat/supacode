//
//  supacodeApp.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import Foundation
import GhosttyKit
import SwiftUI
import ComposableArchitecture
import Sentry

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
  @State private var ghosttyShortcuts: GhosttyShortcutManager
  @State private var terminalManager: WorktreeTerminalManager
  @State private var worktreeInfoWatcher: WorktreeInfoWatcherManager
  @State private var commandKeyObserver: CommandKeyObserver
  @State private var store: StoreOf<AppFeature>

  @MainActor init() {
    #if !DEBUG
    SentrySDK.start { options in
      options.dsn = "https://fb4d394e0bd3e72871b01c7ef3cac129@o1224589.ingest.us.sentry.io/4510770231050240"
      options.tracesSampleRate = 1.0
    }
    #endif
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
    let shortcuts = GhosttyShortcutManager(runtime: runtime)
    _ghosttyShortcuts = State(initialValue: shortcuts)
    let initialSettings = GlobalSettings.default
    let terminalManager = WorktreeTerminalManager(runtime: runtime)
    _terminalManager = State(initialValue: terminalManager)
    let worktreeInfoWatcher = WorktreeInfoWatcherManager()
    _worktreeInfoWatcher = State(initialValue: worktreeInfoWatcher)
    let keyObserver = CommandKeyObserver()
    _commandKeyObserver = State(initialValue: keyObserver)
    let appStore = Store(
      initialState: AppFeature.State(settings: SettingsFeature.State(settings: initialSettings))
    ) {
        AppFeature()
      } withDependencies: { values in
        values.terminalClient = TerminalClient(
          send: { command in
            terminalManager.handleCommand(command)
          },
          events: {
            terminalManager.eventStream()
          }
        )
        values.worktreeInfoWatcher = WorktreeInfoWatcherClient(
          send: { command in
            worktreeInfoWatcher.handleCommand(command)
          },
          events: {
            worktreeInfoWatcher.eventStream()
          }
        )
      }
    _store = State(initialValue: appStore)
    SettingsWindowManager.shared.configure(
      store: appStore,
      ghosttyShortcuts: shortcuts,
      commandKeyObserver: keyObserver
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store, terminalManager: terminalManager)
        .environment(ghosttyShortcuts)
        .environment(commandKeyObserver)
        .preferredColorScheme(store.settings.appearanceMode.colorScheme)
    }
    .environment(ghosttyShortcuts)
    .environment(commandKeyObserver)
    .commands {
      WorktreeCommands(store: store.scope(state: \.repositories, action: \.repositories))
      SidebarCommands()
      TerminalCommands(ghosttyShortcuts: ghosttyShortcuts)
      UpdateCommands(store: store.scope(state: \.updates, action: \.updates))
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          SettingsWindowManager.shared.show()
        }
        .keyboardShortcut(
          AppShortcuts.openSettings.keyEquivalent,
          modifiers: AppShortcuts.openSettings.modifiers
        )
      }
    }
  }
}
