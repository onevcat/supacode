import AppKit
import Combine
import SwiftUI

/// Syncs the NSWindow appearance with the app's appearance mode.
///
/// SwiftUI's `preferredColorScheme` only affects the SwiftUI layer.
/// This representable explicitly sets `NSWindow.appearance` so that
/// AppKit-level chrome (toolbar, NSColor resolution) also follows.
///
/// For System mode, it observes `NSApp.effectiveAppearance` via KVO
/// so the window tracks macOS appearance changes automatically.
struct WindowAppearanceSetter: NSViewRepresentable {
  let appearanceMode: AppearanceMode

  func makeNSView(context: Context) -> WindowAppearanceView {
    let view = WindowAppearanceView()
    view.appearanceMode = appearanceMode
    return view
  }

  func updateNSView(_ nsView: WindowAppearanceView, context: Context) {
    nsView.appearanceMode = appearanceMode
  }
}

final class WindowAppearanceView: NSView {
  var appearanceMode: AppearanceMode = .system {
    didSet {
      guard appearanceMode != oldValue else { return }
      applyAppearance()
    }
  }

  private var appearanceObservation: NSKeyValueObservation?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyAppearance()
  }

  private func applyAppearance() {
    guard let window else { return }
    appearanceObservation = nil

    let name: NSAppearance.Name = appearanceMode.colorScheme == .light ? .aqua : .darkAqua
    if window.appearance?.name != name {
      window.appearance = NSAppearance(named: name)
    }

    if appearanceMode == .system {
      appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) {
        [weak self, weak window] _, _ in
        MainActor.assumeIsolated {
          guard let window else { return }
          let systemName: NSAppearance.Name =
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .darkAqua : .aqua
          if window.appearance?.name != systemName {
            window.appearance = NSAppearance(named: systemName)
          }
          _ = self  // prevent unused warning while retaining weak ref for lifetime
        }
      }
    }
  }
}
