import AppKit
import SwiftUI

struct WindowAppearanceSetter: NSViewRepresentable {
  let colorScheme: ColorScheme?

  func makeNSView(context: Context) -> WindowAppearanceView {
    let view = WindowAppearanceView()
    view.colorScheme = colorScheme
    return view
  }

  func updateNSView(_ nsView: WindowAppearanceView, context: Context) {
    nsView.colorScheme = colorScheme
  }
}

final class WindowAppearanceView: NSView {
  var colorScheme: ColorScheme? {
    didSet {
      guard colorScheme != oldValue else { return }
      applyAppearance()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyAppearance()
  }

  private func applyAppearance() {
    guard let window else { return }
    let desiredName: NSAppearance.Name? = switch colorScheme {
    case .light: .aqua
    case .dark: .darkAqua
    default: nil
    }
    guard window.appearance?.name != desiredName else { return }
    window.appearance = desiredName.flatMap { NSAppearance(named: $0) }
  }
}
