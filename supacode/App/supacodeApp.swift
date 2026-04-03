//
//  supacodeApp.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import AppKit
import ComposableArchitecture
import Foundation
import GhosttyKit
import PostHog
import Sentry
import Sharing
import SwiftUI

private enum GhosttyCLI {
  static func argv(resolvedKeybindings: ResolvedKeybindingMap) -> [UnsafeMutablePointer<CChar>?] {
    var args: [UnsafeMutablePointer<CChar>?] = []
    let executable = CommandLine.arguments.first ?? "supacode"
    args.append(strdup(executable))
    for keybindArgument in AppShortcuts.ghosttyCLIKeybindArguments(from: resolvedKeybindings) {
      args.append(strdup(keybindArgument))
    }
    args.append(nil)
    return args
  }
}

@MainActor
final class SupacodeAppDelegate: NSObject, NSApplicationDelegate {
  var appStore: StoreOf<AppFeature>?
  var terminalManager: WorktreeTerminalManager?
  var cliSocketServer: CLISocketServer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Disable press-and-hold accent menu so that key repeat works in the terminal.
    UserDefaults.standard.register(defaults: [
      "ApplePressAndHoldEnabled": false
    ])
    appStore?.send(.appLaunched)
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    let app = NSApplication.shared
    guard !app.windows.contains(where: \.isVisible) else { return }
    _ = showMainWindow(from: app)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if flag { return true }
    return showMainWindow(from: sender) ? false : true
  }

  func applicationWillTerminate(_ notification: Notification) {
    defer { cliSocketServer?.stop() }
    guard appStore?.state.settings.restoreTerminalLayoutOnLaunch == true else { return }
    guard appStore?.state.suppressLayoutSaveUntilRelaunch != true else { return }
    terminalManager?.persistLayoutSnapshotSync()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  private func mainWindow(from sender: NSApplication) -> NSWindow? {
    if let window = sender.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      return window
    }
    if let window = sender.windows.first(where: { $0.identifier?.rawValue != "settings" }) {
      return window
    }
    return sender.windows.first
  }

  private func showMainWindow(from sender: NSApplication) -> Bool {
    guard let window = mainWindow(from: sender) else { return false }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    sender.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    return true
  }
}

@main
@MainActor
struct SupacodeApp: App {
  @NSApplicationDelegateAdaptor(SupacodeAppDelegate.self) private var appDelegate
  @State private var ghostty: GhosttyRuntime
  @State private var ghosttyShortcuts: GhosttyShortcutManager
  @State private var terminalManager: WorktreeTerminalManager
  @State private var worktreeInfoWatcher: WorktreeInfoWatcherManager
  @State private var commandKeyObserver: CommandKeyObserver
  @State private var cliSocketServer: CLISocketServer
  @State private var store: StoreOf<AppFeature>

  @MainActor init() {
    NSWindow.allowsAutomaticWindowTabbing = false
    UserDefaults.standard.set(200, forKey: "NSInitialToolTipDelay")
    @Shared(.settingsFile) var settingsFile
    let initialSettings = settingsFile.global
    let initialResolvedKeybindings = KeybindingResolver.resolve(
      schema: .appResolverSchema(),
      userOverrides: initialSettings.keybindingUserOverrides
    )
    #if !DEBUG
      if initialSettings.crashReportsEnabled {
        SentrySDK.start { options in
          options.dsn = "__SENTRY_DSN__"
          options.tracesSampleRate = 1.0
          options.enableAppHangTracking = false
        }
      }
      if initialSettings.analyticsEnabled {
        let posthogAPIKey = "__POSTHOG_API_KEY__"
        let posthogHost = "__POSTHOG_HOST__"
        let config = PostHogConfig(apiKey: posthogAPIKey, host: posthogHost)
        config.enableSwizzling = false
        PostHogSDK.shared.setup(config)
        if let hardwareUUID = HardwareInfo.uuid {
          PostHogSDK.shared.identify(hardwareUUID)
        }
      }
    #endif
    if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("ghostty") {
      setenv("GHOSTTY_RESOURCES_DIR", resourceURL.path, 1)
    }
    let ghosttyArgv = GhosttyCLI.argv(resolvedKeybindings: initialResolvedKeybindings)
    ghosttyArgv.withUnsafeBufferPointer { buffer in
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
    let terminalManager = WorktreeTerminalManager(
      runtime: runtime,
      preferredFontSize: initialSettings.terminalFontSize
    )
    _terminalManager = State(initialValue: terminalManager)
    let worktreeInfoWatcher = WorktreeInfoWatcherManager()
    _worktreeInfoWatcher = State(initialValue: worktreeInfoWatcher)
    let keyObserver = CommandKeyObserver()
    _commandKeyObserver = State(initialValue: keyObserver)
    let appStore = Store(
      initialState: AppFeature.State(settings: SettingsFeature.State(settings: initialSettings))
    ) {
      AppFeature()
        .logActions()
    } withDependencies: { values in
      values.terminalClient = TerminalClient(
        send: { command in
          terminalManager.handleCommand(command)
        },
        events: {
          terminalManager.eventStream()
        },
        canvasFocusedWorktreeID: {
          terminalManager.canvasFocusedWorktreeID
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

    let cliServer = Self.makeCLISocketServer(appStore: appStore, terminalManager: terminalManager)
    _cliSocketServer = State(initialValue: cliServer)

    runtime.onQuit = { [weak appStore] in
      appStore?.send(.requestQuit)
    }
    appDelegate.appStore = appStore
    appDelegate.terminalManager = terminalManager
    appDelegate.cliSocketServer = cliServer
    SettingsWindowManager.shared.configure(
      store: appStore,
      ghosttyShortcuts: shortcuts,
      commandKeyObserver: keyObserver
    )
  }

  private static func makeCLISocketServer(
    appStore: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager
  ) -> CLISocketServer {
    let listHandler = ListCommandHandler {
      ListRuntimeSnapshotBuilder.makeSnapshot(
        repositoriesState: appStore.state.repositories,
        terminalManager: terminalManager
      )
    }
    let sendHandler = SendCommandHandler(
      resolveProvider: { selector in
        let resolver = TargetResolver {
          TargetResolutionSnapshotBuilder.makeSnapshot(
            repositoriesState: appStore.state.repositories,
            terminalManager: terminalManager
          )
        }
        return resolver.resolve(selector).map { SendResolvedTarget(from: $0) }
      },
      textDelivery: { target, text, trailingEnter in
        guard let state = terminalManager.stateIfExists(for: target.worktreeID) else { return }
        let delivery = CLISendTextDelivery(
          insertText: { paneID, payload in
            state.insertCommittedText(payload, in: paneID)
          },
          submitLine: { paneID in
            state.submitLine(in: paneID)
          }
        )
        delivery.deliver(to: target, text: text, trailingEnter: trailingEnter)
      },
      waiterProvider: { worktreeID, surfaceID in
        terminalManager.stateIfExists(for: worktreeID)?
          .waitForCommandFinished(surfaceID: surfaceID)
      }
    )
    let focusHandler = FocusCommandHandler(
      resolveProvider: { selector in
        let resolver = TargetResolver {
          TargetResolutionSnapshotBuilder.makeSnapshot(
            repositoriesState: appStore.state.repositories,
            terminalManager: terminalManager
          )
        }
        return resolver.resolve(selector).map { FocusResolvedTarget(from: $0) }
      },
      focusPerformer: { target in
        selectCLIWorktreeContext(
          worktreeID: target.worktreeID,
          appStore: appStore,
          terminalManager: terminalManager
        )
        guard let state = terminalManager.stateIfExists(for: target.worktreeID) else {
          return false
        }
        return state.focusSurface(id: target.paneID)
      },
      bringToFront: {
        bringMainWindowToFront()
      }
    )
    let cliRouter = CLICommandRouter(
      listHandler: listHandler,
      focusHandler: focusHandler,
      sendHandler: sendHandler
    )
    let cliServer = CLISocketServer(router: cliRouter)
    let logger = SupaLogger("CLIService")
    do {
      try cliServer.start()
      logger.info("CLI socket server started at \(ProwlSocket.defaultPath)")
    } catch {
      logger.warning("Failed to start CLI socket server: \(String(describing: error))")
    }
    return cliServer
  }

  private static func selectCLIWorktreeContext(
    worktreeID: Worktree.ID,
    appStore: StoreOf<AppFeature>,
    terminalManager: WorktreeTerminalManager
  ) {
    let repositories = appStore.state.repositories
    if repositories.worktree(for: worktreeID) != nil {
      appStore.send(.repositories(.selectWorktree(worktreeID)))
    } else if let repository = repositories.repositories[id: worktreeID],
      repository.capabilities.supportsRunnableFolderActions
    {
      appStore.send(.repositories(.selectRepository(worktreeID)))
    }
    terminalManager.handleCommand(.setSelectedWorktreeID(worktreeID))
  }

  private static func bringMainWindowToFront() -> Bool {
    let app = NSApplication.shared
    guard let window = mainWindow(from: app) else {
      return false
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    return true
  }

  private static func mainWindow(from app: NSApplication) -> NSWindow? {
    if let window = app.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      return window
    }
    if let window = app.windows.first(where: { $0.identifier?.rawValue != "settings" }) {
      return window
    }
    return app.windows.first
  }

  var body: some Scene {
    Window("Prowl", id: "main") {
      GhosttyColorSchemeSyncView(ghostty: ghostty) {
        ContentView(store: store, terminalManager: terminalManager)
          .environment(ghosttyShortcuts)
          .environment(commandKeyObserver)
          .environment(\.resolvedKeybindings, store.resolvedKeybindings)
      }
      .onAppear {
        syncGhosttyManagedShortcuts(with: store.resolvedKeybindings)
      }
      .onChange(of: store.resolvedKeybindings) { _, newValue in
        syncGhosttyManagedShortcuts(with: newValue)
      }
      .preferredColorScheme(store.settings.appearanceMode.colorScheme)
    }
    .environment(ghosttyShortcuts)
    .environment(commandKeyObserver)
    .commands {
      WorktreeCommands(store: store)
      SidebarCommands(store: store)
      TerminalCommands(ghosttyShortcuts: ghosttyShortcuts)
      WindowCommands(
        ghosttyShortcuts: ghosttyShortcuts,
        resolvedKeybindings: store.resolvedKeybindings
      )
      CommandGroup(after: .textEditing) {
        Button("Command Palette") {
          store.send(.commandPalette(.togglePresented))
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: store.resolvedKeybindings.keyboardShortcut(
              for: AppShortcuts.CommandID.commandPalette
            )
          )
        )
        .help(helpText(title: "Command Palette", commandID: AppShortcuts.CommandID.commandPalette))
      }
      UpdateCommands(
        store: store.scope(state: \.updates, action: \.updates),
        resolvedKeybindings: store.resolvedKeybindings
      )
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          SettingsWindowManager.shared.show()
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: store.resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.openSettings)
          )
        )
      }
      CommandGroup(replacing: .appTermination) {
        Button("Quit Prowl") {
          store.send(.requestQuit)
        }
        .modifier(
          KeyboardShortcutModifier(
            shortcut: store.resolvedKeybindings.keyboardShortcut(
              for: AppShortcuts.CommandID.quitApplication
            )
          )
        )
        .help(helpText(title: "Quit Prowl", commandID: AppShortcuts.CommandID.quitApplication))
      }
    }
  }

  private func syncGhosttyManagedShortcuts(with resolvedKeybindings: ResolvedKeybindingMap) {
    ghostty.applyAppKeybindArguments(
      AppShortcuts.ghosttyCLIKeybindArguments(from: resolvedKeybindings)
    )
  }

  private func helpText(title: String, commandID: String) -> String {
    if let shortcut = store.resolvedKeybindings.display(for: commandID) {
      return "\(title) (\(shortcut))"
    }
    return title
  }
}
