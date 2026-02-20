import SwiftUI

struct TerminalTabsOverflowShadow: View {
  var width: CGFloat
  var startPoint: UnitPoint
  var endPoint: UnitPoint

  @Environment(\.controlActiveState)
  private var activeState
  @Environment(\.surfaceChromeBackgroundOpacity)
  private var surfaceChromeBackgroundOpacity

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
      TerminalTabBarColors.barBackground.opacity(chromeBackgroundOpacity),
      TerminalTabBarColors.barBackground.opacity(0),
    ]
  }

  private var chromeBackgroundOpacity: Double {
    let baseOpacity = surfaceChromeBackgroundOpacity
    if activeState == .inactive {
      return baseOpacity * 0.95
    }
    return baseOpacity
  }
}
