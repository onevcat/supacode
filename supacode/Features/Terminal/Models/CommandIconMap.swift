import Foundation

/// Resolves a tab icon from a command title surfaced by the
/// auto-detector (typically the OSC 2 title set by the shell's
/// `preexec`).
///
/// Lookup is case-insensitive on the *first whitespace-delimited
/// token*. Examples: `"swift build"` and `"swift test"` route through
/// the `swift` entry; `"claude"` routes through `claude`.
///
/// Returns `nil` when nothing matches; the auto-detector then leaves
/// the tab's existing icon untouched (selection-2 semantics — a
/// previously-detected icon is preserved across unknown commands).
enum CommandIconMap {
  static func iconForFirstToken(_ title: String) -> TabIconSource? {
    let token = firstToken(of: title).lowercased()
    return firstTokenMapping[token]
  }

  private static func firstToken(of title: String) -> String {
    title
      .split(separator: " ", omittingEmptySubsequences: true)
      .first
      .map(String.init)
      ?? title
  }

  /// First-token table. Grouped by category and alphabetised within
  /// each group. SF Symbols only at this layer keep things glanceable
  /// before asset rendering is wired; entries that ship branded
  /// artwork should add `assetName:` and let renderers prefer it.
  private static let firstTokenMapping: [String: TabIconSource] = [
    // Coding agents
    "claude": TabIconSource(systemSymbol: "sparkle", assetName: "ClaudeCode"),
    "codex": TabIconSource(systemSymbol: "sparkle", assetName: "Codex"),
    "aider": TabIconSource(systemSymbol: "sparkle"),

    // Editors / pagers
    "vim": TabIconSource(systemSymbol: "pencil.and.scribble", assetName: "Vim"),
    "nvim": TabIconSource(systemSymbol: "pencil.and.scribble", assetName: "Neovim"),
    "nano": TabIconSource(systemSymbol: "pencil.and.scribble"),

    // Package managers / JS runtimes
    "npm": TabIconSource(systemSymbol: "shippingbox", assetName: "Npm"),
    "pnpm": TabIconSource(systemSymbol: "shippingbox", assetName: "Pnpm"),
    "yarn": TabIconSource(systemSymbol: "shippingbox", assetName: "Yarn"),
    "bun": TabIconSource(systemSymbol: "shippingbox", assetName: "Bun"),

    // VCS
    "git": TabIconSource(systemSymbol: "arrow.triangle.branch", assetName: "Git"),
    "gh": TabIconSource(systemSymbol: "arrow.triangle.branch", assetName: "GitHub"),

    // Build tools
    "make": TabIconSource(systemSymbol: "hammer"),
    "swift": TabIconSource(systemSymbol: "hammer", assetName: "Swift"),
    "cargo": TabIconSource(systemSymbol: "hammer", assetName: "Rust"),
    "xcodebuild": TabIconSource(systemSymbol: "hammer", assetName: "Xcode"),
    "gradle": TabIconSource(systemSymbol: "hammer", assetName: "Gradle"),

    // Container / orchestration
    "docker": TabIconSource(systemSymbol: "shippingbox.fill", assetName: "Docker"),
    "kubectl": TabIconSource(systemSymbol: "shippingbox.fill", assetName: "Kubernetes"),
    "podman": TabIconSource(systemSymbol: "shippingbox.fill", assetName: "Podman"),

    // Network / remote
    "ssh": TabIconSource(systemSymbol: "network"),
    "mosh": TabIconSource(systemSymbol: "network"),
    "curl": TabIconSource(systemSymbol: "network", assetName: "Curl"),

    // Process / system viewers
    "htop": TabIconSource(systemSymbol: "waveform.path.ecg"),
    "btop": TabIconSource(systemSymbol: "waveform.path.ecg"),
    "top": TabIconSource(systemSymbol: "waveform.path.ecg"),

    // Database REPLs
    "psql": TabIconSource(systemSymbol: "cylinder.split.1x2", assetName: "PostgreSQL"),
    "mysql": TabIconSource(systemSymbol: "cylinder.split.1x2", assetName: "MySQL"),
    "sqlite3": TabIconSource(systemSymbol: "cylinder.split.1x2", assetName: "SQLite"),

    // Logs / streams
    "tail": TabIconSource(systemSymbol: "text.justifyleft"),
    "journalctl": TabIconSource(systemSymbol: "text.justifyleft"),
  ]
}
