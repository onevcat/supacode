import SwiftUI

struct TerminalTabBarBackground: View {
  @Environment(\.controlActiveState)
  private var activeState
  @Environment(\.colorScheme)
  private var colorScheme
  @Environment(\.surfaceTopChromeBackgroundOpacity)
  private var surfaceTopChromeBackgroundOpacity

  var body: some View {
    Rectangle()
      .fill(barBackground.opacity(chromeBackgroundOpacity))
  }

  // Use colorScheme from SwiftUI environment to resolve the right color,
  // since Color(nsColor:) in toolbar context may not follow preferredColorScheme.
  private var barBackground: Color {
    let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    var resolved: NSColor = .windowBackgroundColor
    appearance?.performAsCurrentDrawingAppearance {
      resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .windowBackgroundColor
    }
    return Color(nsColor: resolved)
  }

  private var chromeBackgroundOpacity: Double {
    let baseOpacity = surfaceTopChromeBackgroundOpacity
    if activeState == .inactive {
      return baseOpacity * 0.95
    }
    return baseOpacity
  }
}
