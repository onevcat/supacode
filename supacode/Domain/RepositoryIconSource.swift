import Foundation

/// Where a repository's icon comes from. Storage is a single string so
/// the on-disk JSON stays compact and migration-friendly; the marker
/// convention mirrors `TabIconSource` / `ResolvedTabIcon` so a future
/// reader looking at one knows the other.
///
/// - `sfSymbol`: a system SF Symbol name; tintable.
/// - `bundledAsset`: a name from the app's asset catalog (reserved for
///   future branded presets; not user-importable).
/// - `userImage`: a file the user dropped in via the picker, stored at
///   `~/.prowl/repo/<name>/icons/<filename>`. Filename includes its
///   extension so `isTintable` can distinguish PNG (no tint) from SVG.
nonisolated enum RepositoryIconSource: Equatable, Hashable, Sendable {
  case sfSymbol(String)
  case bundledAsset(String)
  case userImage(filename: String)

  static let assetMarker = "@asset:"
  static let userImageMarker = "@file:"

  /// Round-tripped form for JSON storage. Bare strings stay SF Symbols
  /// for forward-compat with anything else that learns the convention.
  var storageString: String {
    switch self {
    case .sfSymbol(let name):
      name
    case .bundledAsset(let name):
      Self.assetMarker + name
    case .userImage(let filename):
      Self.userImageMarker + filename
    }
  }

  /// Inverse of `storageString`. Returns `nil` for empty input so
  /// callers can treat "no icon" and "blank string" identically.
  static func parse(_ raw: String) -> RepositoryIconSource? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix(userImageMarker) {
      return .userImage(filename: String(trimmed.dropFirst(userImageMarker.count)))
    }
    if trimmed.hasPrefix(assetMarker) {
      return .bundledAsset(String(trimmed.dropFirst(assetMarker.count)))
    }
    return .sfSymbol(trimmed)
  }

  /// PNG keeps its own colors; SF Symbols and SVGs are tintable. Bundled
  /// assets default to non-tintable so future additions don't repaint
  /// branded artwork unintentionally — flip per-asset if/when needed.
  var isTintable: Bool {
    switch self {
    case .sfSymbol:
      true
    case .bundledAsset:
      false
    case .userImage(let filename):
      filename.lowercased().hasSuffix(".svg")
    }
  }
}

extension RepositoryIconSource: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let parsed = Self.parse(raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Empty repository icon storage string"
      )
    }
    self = parsed
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(storageString)
  }
}
