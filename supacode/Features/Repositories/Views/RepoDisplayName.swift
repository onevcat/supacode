import Sharing
import SwiftUI

/// Renders the repository display label, preferring the user's custom
/// title from `RepositorySettings` over the folder-derived fallback.
///
/// Subscription is isolated to this leaf view so callers don't pull in
/// `@Shared(.repositorySettings(...))` themselves and parent views
/// don't churn on settings changes. Mirrors the per-leaf-subscription
/// pattern used by `RepoHeaderTabCountBadge`.
///
/// The view emits a plain `Text` — callers apply their own font /
/// foreground style modifiers so this view stays appearance-agnostic.
struct RepoDisplayName: View {
  let fallbackName: String
  let repositoryRootURL: URL?
  var tooltip: String?

  var body: some View {
    if let repositoryRootURL {
      RepoDisplayNameResolved(
        rootURL: repositoryRootURL,
        fallbackName: fallbackName,
        tooltip: tooltip
      )
    } else {
      Text(fallbackName)
        .help(tooltip ?? "")
    }
  }
}

private struct RepoDisplayNameResolved: View {
  let fallbackName: String
  let tooltip: String?
  @Shared private var settings: RepositorySettings

  init(rootURL: URL, fallbackName: String, tooltip: String?) {
    self.fallbackName = fallbackName
    self.tooltip = tooltip
    _settings = Shared(wrappedValue: .default, .repositorySettings(rootURL))
  }

  var body: some View {
    Text(settings.customTitle ?? fallbackName)
      .help(tooltip ?? "")
  }
}
