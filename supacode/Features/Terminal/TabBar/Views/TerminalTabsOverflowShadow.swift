import SwiftUI

struct TerminalTabsOverflowShadow: View {
  var width: CGFloat
  var startPoint: UnitPoint
  var endPoint: UnitPoint

  @Environment(\.controlActiveState)
  private var activeState
  @Environment(\.colorScheme)
  private var colorScheme
  @Environment(\.surfaceTopChromeBackgroundOpacity)
  private var surfaceTopChromeBackgroundOpacity

  var body: some View {
    Rectangle()
      .frame(maxHeight: .infinity)
      .frame(width: width)
      .foregroundStyle(.clear)
      .background(
        LinearGradient(
          gradient: Gradient(colors: gradientColors),
          startPoint: startPoint,
          endPoint: endPoint
        )
      )
      .allowsHitTesting(false)
  }

  private var gradientColors: [Color] {
    [
      barBackground.opacity(chromeBackgroundOpacity),
      barBackground.opacity(0),
    ]
  }

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
