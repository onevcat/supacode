import SwiftUI

private struct GhosttyMonospacedStyleModifier: ViewModifier {
  @Environment(GhosttyFontManager.self) private var ghosttyFonts
  let style: Font.TextStyle

  func body(content: Content) -> some View {
    content.font(ghosttyFonts.font(for: style))
  }
}

private struct GhosttyMonospacedSizeModifier: ViewModifier {
  @Environment(GhosttyFontManager.self) private var ghosttyFonts
  let size: CGFloat
  let weight: Font.Weight

  func body(content: Content) -> some View {
    content.font(ghosttyFonts.font(size: size, weight: weight))
  }
}

extension View {
  func ghosttyMonospaced(_ style: Font.TextStyle) -> some View {
    modifier(GhosttyMonospacedStyleModifier(style: style))
  }

  func ghosttyMonospaced(size: CGFloat, weight: Font.Weight = .regular) -> some View {
    modifier(GhosttyMonospacedSizeModifier(size: size, weight: weight))
  }
}
