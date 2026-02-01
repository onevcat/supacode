import AppKit
import SwiftUI

struct WindowTabbingDisabler: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowTabbingView {
    WindowTabbingView()
  }

  func updateNSView(_ nsView: WindowTabbingView, context: Context) {
    nsView.disallowTabbing()
  }
}

final class WindowTabbingView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    disallowTabbing()
  }

  func disallowTabbing() {
    window?.tabbingMode = .disallowed
  }
}
