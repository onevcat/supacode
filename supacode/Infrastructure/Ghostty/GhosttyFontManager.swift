import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class GhosttyFontManager {
  private let runtime: GhosttyRuntime
  private var observer: NSObjectProtocol?
  private var familyName: String?

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
    refresh()
    observer = NotificationCenter.default.addObserver(
      forName: .ghosttyRuntimeConfigDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  @MainActor deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func font(for style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
    let size = preferredSize(for: style)
    if familyName != nil {
      let nsWeight = weight.map(nsWeight(for:)) ?? preferredWeight(for: style)
      return Font(nsFont(size: size, weight: nsWeight))
    }
    if let weight {
      return .system(style, design: .monospaced).weight(weight)
    }
    return .system(style, design: .monospaced)
  }

  func font(size: CGFloat, weight: Font.Weight? = nil) -> Font {
    if familyName != nil {
      let nsWeight = weight.map(nsWeight(for:)) ?? .regular
      return Font(nsFont(size: size, weight: nsWeight))
    }
    let resolvedWeight = weight ?? .regular
    return .system(size: size, weight: resolvedWeight, design: .monospaced)
  }

  func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    guard let familyName else {
      return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    let descriptor = NSFontDescriptor(fontAttributes: [
      .family: familyName,
      .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
    ])
    if let font = NSFont(descriptor: descriptor, size: size) {
      return font
    }
    if let font = NSFont(name: familyName, size: size) {
      return font
    }
    return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }

  private func refresh() {
    familyName = runtime.primaryFontFamilyName()
  }

  private func preferredSize(for style: Font.TextStyle) -> CGFloat {
    NSFont.preferredFont(forTextStyle: nsTextStyle(for: style)).pointSize
  }

  private func preferredWeight(for style: Font.TextStyle) -> NSFont.Weight {
    let font = NSFont.preferredFont(forTextStyle: nsTextStyle(for: style))
    let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
    let weight = traits?[.weight] as? CGFloat
    return NSFont.Weight(weight ?? NSFont.Weight.regular.rawValue)
  }

  private func nsWeight(for weight: Font.Weight) -> NSFont.Weight {
    switch weight {
    case .ultraLight:
      return .ultraLight
    case .thin:
      return .thin
    case .light:
      return .light
    case .regular:
      return .regular
    case .medium:
      return .medium
    case .semibold:
      return .semibold
    case .bold:
      return .bold
    case .heavy:
      return .heavy
    case .black:
      return .black
    default:
      return .regular
    }
  }

  private func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
    switch style {
    case .largeTitle:
      return .largeTitle
    case .title:
      return .title1
    case .title2:
      return .title2
    case .title3:
      return .title3
    case .headline:
      return .headline
    case .subheadline:
      return .subheadline
    case .body:
      return .body
    case .callout:
      return .callout
    case .footnote:
      return .footnote
    case .caption:
      return .caption1
    case .caption2:
      return .caption2
    @unknown default:
      return .body
    }
  }
}
