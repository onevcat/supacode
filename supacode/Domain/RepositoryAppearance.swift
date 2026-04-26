import Foundation

/// User-pinned visual identity for a single repository: an optional
/// icon source and an optional color choice, both freely combinable.
/// Both fields are independently optional so a user can color-tag a
/// repo without picking an icon (and vice versa).
///
/// Persisted as part of a global `[Repository.ID: RepositoryAppearance]`
/// dictionary — not nested in `Repository` or `RepositorySettings` —
/// because the sidebar / shelf / canvas all need O(1) cross-repo
/// lookups during render and a single `@Shared` dict is the lightest
/// way to give every renderer the same view.
nonisolated struct RepositoryAppearance: Codable, Equatable, Hashable, Sendable {
  var icon: RepositoryIconSource?
  var color: RepositoryColorChoice?

  static let empty = RepositoryAppearance(icon: nil, color: nil)

  init(icon: RepositoryIconSource? = nil, color: RepositoryColorChoice? = nil) {
    self.icon = icon
    self.color = color
  }

  var isEmpty: Bool {
    icon == nil && color == nil
  }
}
