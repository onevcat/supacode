import SwiftUI

struct RepoHeaderRow: View {
  private static let debugHeaderLayers = false
  let name: String
  let isRemoving: Bool
  let tabCount: Int
  /// User-pinned icon, when set. Renders before the repo name.
  /// `nil` keeps the historical text-only layout intact.
  let icon: RepositoryIconSource?
  /// Resolved tint applied to tintable icons (SF Symbols / SVGs).
  /// PNGs and bundled assets ignore this and render their own colors.
  let iconTint: Color?
  /// Repo root URL — needed by `RepositoryIconImage` to resolve
  /// user-imported image filenames into absolute file URLs.
  let repositoryRootURL: URL?
  var nameTooltip: String?

  var body: some View {
    HStack {
      if let icon, let repositoryRootURL {
        RepositoryIconImage(
          icon: icon,
          repositoryRootURL: repositoryRootURL,
          tintColor: iconTint,
          size: 14
        )
      }
      Text(name)
        .foregroundStyle(.secondary)
        .help(nameTooltip ?? "")
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      if tabCount > 0 {
        Text("\(tabCount)")
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: .capsule)
          .help("\(tabCount) active \(tabCount == 1 ? "tab" : "tabs")")
      }
    }
    .background {
      if Self.debugHeaderLayers {
        Rectangle()
          .fill(.cyan.opacity(0.18))
          .overlay {
            Rectangle()
              .stroke(.cyan, lineWidth: 1)
          }
      }
    }
  }
}

// MARK: - Previews

#Preview("RepoHeaderRow") {
  VStack(alignment: .leading, spacing: 12) {
    RepoHeaderRow(
      name: "supacode",
      isRemoving: false,
      tabCount: 3,
      icon: nil,
      iconTint: nil,
      repositoryRootURL: nil
    )
    RepoHeaderRow(
      name: "ghostty",
      isRemoving: false,
      tabCount: 0,
      icon: .sfSymbol("folder.fill"),
      iconTint: .blue,
      repositoryRootURL: URL(fileURLWithPath: "/tmp/ghostty")
    )
    RepoHeaderRow(
      name: "removing-repo",
      isRemoving: true,
      tabCount: 1,
      icon: .sfSymbol("hammer.fill"),
      iconTint: .orange,
      repositoryRootURL: URL(fileURLWithPath: "/tmp/removing")
    )
  }
  .padding()
}
