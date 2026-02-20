import SwiftUI

struct TerminalTabBarBackground: View {
  @Environment(\.controlActiveState)
  private var activeState
  @Environment(\.surfaceChromeBackgroundOpacity)
  private var surfaceChromeBackgroundOpacity

  var body: some View {
    Rectangle()
      .fill(TerminalTabBarColors.barBackground.opacity(chromeBackgroundOpacity))
  }

  private var chromeBackgroundOpacity: Double {
    let baseOpacity = surfaceChromeBackgroundOpacity
    if activeState == .inactive {
      return baseOpacity * 0.95
    }
    return baseOpacity
  }
}
