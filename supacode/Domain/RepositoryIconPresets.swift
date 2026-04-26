import Foundation

/// Repository-flavored SF Symbol picker presets. These are surfaced by
/// `RepositoryAppearancePickerView` (which reuses `TabIconPickerView`
/// with this list), distinct from the terminal-themed list the tab
/// picker ships. The split exists because the same picker is used in
/// two contexts that reach for different vocabulary: a tab picker
/// favors `play.fill` / `terminal` / `ladybug.fill`, a repo picker
/// favors `folder.fill` / `cube.fill` / `book.fill`.
///
/// Order is loosely thematic so scanning the grid surfaces intent:
/// folders → boxes/data → tools → web/server → tech → ornament.
nonisolated enum RepositoryIconPresets {
  static let presets: [String] = [
    "folder.fill",
    "folder",
    "folder.badge.gearshape",
    "tray.full.fill",
    "tray.2.fill",
    "shippingbox.fill",
    "cube.fill",
    "cube.transparent",
    "doc.text.fill",
    "doc.fill",
    "book.fill",
    "books.vertical.fill",
    "hammer.fill",
    "wrench.and.screwdriver.fill",
    "screwdriver.fill",
    "paintpalette.fill",
    "paintbrush.fill",
    "globe",
    "network",
    "server.rack",
    "cloud.fill",
    "cpu",
    "gearshape.fill",
    "swift",
    "ladybug.fill",
    "leaf.fill",
    "star.fill",
    "heart.fill",
    "bolt.fill",
    "sparkles",
    "flame.fill",
    "rocket.fill",
    "tag.fill",
    "bookmark.fill",
    "flag.fill",
    "circle.hexagongrid.fill",
  ]
}
