import AppKit
import CoreText
import GhosttyKit
import Observation
import SwiftUI

@MainActor
@Observable
final class GhosttyFontManager {
  private let probeSurface: GhosttySurfaceView
  private var observer: NSObjectProtocol?
  private var familyName: String?

  init(runtime: GhosttyRuntime) {
    self.probeSurface = GhosttySurfaceView(runtime: runtime, workingDirectory: nil)
    refresh()
    observer = NotificationCenter.default.addObserver(
      forName: .ghosttyRuntimeConfigDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refresh()
    }
  }

  @MainActor deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func font(for style: Font.TextStyle) -> Font {
    if let familyName {
      let size = preferredSize(for: style)
      return .custom(familyName, size: size, relativeTo: style)
    }
    return .system(style, design: .monospaced)
  }

  func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    if let familyName {
      return .custom(familyName, size: size).weight(weight)
    }
    return .system(size: size, weight: weight, design: .monospaced)
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
    familyName = resolveFamilyName()
  }

  private func resolveFamilyName() -> String? {
    guard let surface = probeSurface.surface else { return nil }
    guard let fontRaw = ghostty_surface_quicklook_font(surface) else { return nil }
    let unmanaged = Unmanaged<CTFont>.fromOpaque(fontRaw)
    let font = unmanaged.takeUnretainedValue()
    let name = CTFontCopyFamilyName(font) as String
    unmanaged.release()
    return name.isEmpty ? nil : name
  }

  private func preferredSize(for style: Font.TextStyle) -> CGFloat {
    NSFont.preferredFont(forTextStyle: nsTextStyle(for: style)).pointSize
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
