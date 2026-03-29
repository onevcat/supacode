import SwiftUI

/// Color token for terminal tab tint indicators, used in place of
/// `Color` so that `TerminalTabItem` can remain `Equatable` and `Sendable`.
enum TerminalTabTintColor: Hashable, Sendable {
  case green
  case orange
  case red

  var color: Color {
    switch self {
    case .green: .green
    case .orange: .orange
    case .red: .red
    }
  }
}
