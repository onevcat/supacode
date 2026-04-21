/// Which presentation the app enters on launch. `normal` keeps the
/// historical behavior (sidebar + terminal detail); `shelf` boots
/// straight into Shelf so power users who live in Shelf don't have to
/// toggle it every time they open Prowl.
enum DefaultViewMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case normal
  case shelf

  var id: String { rawValue }

  var title: String {
    switch self {
    case .normal:
      return "Normal View"
    case .shelf:
      return "Shelf View"
    }
  }
}
