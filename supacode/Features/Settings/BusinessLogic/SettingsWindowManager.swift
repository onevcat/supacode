import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class SettingsWindowManager {
  static let shared = SettingsWindowManager()

  private var settingsWindow: NSWindow?
  private var store: StoreOf<AppFeature>?
  private var ghosttyShortcuts: GhosttyShortcutManager?
  private var commandKeyObserver: CommandKeyObserver?

  private init() {}

  func configure(
    store: StoreOf<AppFeature>,
    ghosttyShortcuts: GhosttyShortcutManager,
    commandKeyObserver: CommandKeyObserver
  ) {
    self.store = store
    self.ghosttyShortcuts = ghosttyShortcuts
    self.commandKeyObserver = commandKeyObserver
  }

  func show() {
    if let existingWindow = settingsWindow {
      if existingWindow.isMiniaturized {
        existingWindow.deminiaturize(nil)
      }
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }

    guard let store, let ghosttyShortcuts, let commandKeyObserver else { return }
    let settingsView = SettingsView(store: store)
      .environment(ghosttyShortcuts)
      .environment(commandKeyObserver)
    let hostingController = NSHostingController(rootView: settingsView)

    let window = NSWindow(contentViewController: hostingController)
    window.title = ""
    window.titleVisibility = .hidden
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.toolbar = NSToolbar(identifier: "SettingsToolbar")
    if #unavailable(macOS 15.0) {
      window.toolbar?.showsBaselineSeparator = false
    }
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 800, height: 600))
    window.minSize = NSSize(width: 750, height: 500)

    window.center()
    window.makeKeyAndOrderFront(nil)

    settingsWindow = window
  }
}
