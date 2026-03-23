import AppKit
import SwiftUI

@MainActor
final class GitLogWindowManager {
  static let shared = GitLogWindowManager()

  let state = GitLogWindowState()
  private var window: NSWindow?
  private var localEventMonitor: Any?

  private init() {}

  func show(worktreeURL: URL, branchName: String) {
    state.load(worktreeURL: worktreeURL, branchName: branchName)

    if let existingWindow = window {
      existingWindow.title = windowTitle(branchName: branchName)
      if existingWindow.isMiniaturized {
        existingWindow.deminiaturize(nil)
      }
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }

    let contentView = GitLogWindowContentView(state: state)
    let hostingController = NSHostingController(rootView: contentView)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = windowTitle(branchName: branchName)
    newWindow.identifier = NSUserInterfaceItemIdentifier("gitlog")
    newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    newWindow.tabbingMode = .disallowed
    newWindow.toolbarStyle = .unified
    newWindow.toolbar = NSToolbar(identifier: "GitLogToolbar")
    newWindow.isReleasedWhenClosed = false
    newWindow.minSize = NSSize(width: 700, height: 500)
    let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame GitLogWindow") != nil
    newWindow.setFrameAutosaveName("GitLogWindow")
    if !hasSavedFrame {
      newWindow.setContentSize(NSSize(width: 1100, height: 750))
      newWindow.center()
    }
    newWindow.makeKeyAndOrderFront(nil)

    window = newWindow

    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, window == event.window else { return event }
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
        event.charactersIgnoringModifiers == "w"
      {
        window.performClose(nil)
        return nil
      }
      return event
    }
  }

  private func windowTitle(branchName: String) -> String {
    "Git Log — \(branchName)"
  }
}
