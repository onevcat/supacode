import AppKit
import SwiftUI

struct WindowFocusObserverView: NSViewRepresentable {
  let onWindowKeyChanged: (Bool) -> Void
  let onWindowOcclusionChanged: (Bool) -> Void

  func makeNSView(context: Context) -> WindowFocusObserverNSView {
    let view = WindowFocusObserverNSView()
    view.onWindowKeyChanged = onWindowKeyChanged
    view.onWindowOcclusionChanged = onWindowOcclusionChanged
    return view
  }

  func updateNSView(_ nsView: WindowFocusObserverNSView, context: Context) {
    nsView.onWindowKeyChanged = onWindowKeyChanged
    nsView.onWindowOcclusionChanged = onWindowOcclusionChanged
  }
}

final class WindowFocusObserverNSView: NSView {
  var onWindowKeyChanged: (Bool) -> Void = { _ in }
  var onWindowOcclusionChanged: (Bool) -> Void = { _ in }
  private var observers: [NSObjectProtocol] = []
  private weak var observedWindow: NSWindow?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateObservers()
  }

  func notifyCurrentState() {
    onWindowKeyChanged(windowIsKey)
    onWindowOcclusionChanged(windowIsVisible)
  }

  private var windowIsKey: Bool {
    guard let window else { return false }
    return window.isKeyWindow
  }

  private var windowIsVisible: Bool {
    guard let window else { return false }
    return window.occlusionState.contains(.visible)
  }

  private func updateObservers() {
    if observedWindow === window {
      notifyCurrentState()
      return
    }
    clearObservers()
    observedWindow = window
    guard let window else {
      onWindowKeyChanged(false)
      onWindowOcclusionChanged(false)
      return
    }
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.notifyCurrentState()
      })
    observers.append(
      center.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.notifyCurrentState()
      })
    observers.append(
      center.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.notifyCurrentState()
      })
    notifyCurrentState()
  }

  private func clearObservers() {
    let center = NotificationCenter.default
    for observer in observers {
      center.removeObserver(observer)
    }
    observers.removeAll()
  }

  deinit {
    clearObservers()
  }
}
