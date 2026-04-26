import SwiftUI

/// One of a fixed palette of system-provided colors a user can pin to a
/// repository to make it identifiable in the sidebar, shelf spine, and
/// canvas card title bar. The palette is intentionally closed (10 colors)
/// to align with macOS Finder's tag colors and to keep `repoColor` a
/// purely semantic system color — never a custom hex — per the project's
/// "system provided only" rule.
///
/// Persistence: encoded as the raw `String` (case name). New cases are
/// safe to append; cases must never be renamed once shipped because user
/// JSON references them by name.
nonisolated enum RepositoryColorChoice: String, Codable, CaseIterable, Sendable, Hashable {
  case red
  case orange
  case yellow
  case green
  case mint
  case cyan
  case blue
  case purple
  case pink
  case gray

  /// User-facing label for the color picker.
  var displayName: String {
    switch self {
    case .red: "Red"
    case .orange: "Orange"
    case .yellow: "Yellow"
    case .green: "Green"
    case .mint: "Mint"
    case .cyan: "Cyan"
    case .blue: "Blue"
    case .purple: "Purple"
    case .pink: "Pink"
    case .gray: "Gray"
    }
  }

  /// Resolved SwiftUI color. Only the bare named system colors are used
  /// — never custom RGB — so the palette adapts to light/dark mode and
  /// any future system tweaks.
  var color: Color {
    switch self {
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .mint: .mint
    case .cyan: .cyan
    case .blue: .blue
    case .purple: .purple
    case .pink: .pink
    case .gray: .gray
    }
  }
}
