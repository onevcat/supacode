import Dependencies
import Foundation

/// File-system gateway for user-imported repository icon images. Wraps
/// the actual disk operations behind closures so both the live build
/// (real `FileManager`) and tests (in-memory) can drive the same code
/// paths without forking implementations.
///
/// All filenames returned by the store are bare names (e.g.
/// `"3F2D…ABC.svg"`) — never absolute paths — so the persisted
/// `RepositoryAppearance.icon` stays portable: moving a repository
/// directory takes its icons with it without rewriting JSON.
nonisolated struct RepositoryIconAssetStore: Sendable {
  /// Imports a user-picked image into the per-repo icons directory and
  /// returns the bare filename to persist. The implementation chooses
  /// the filename (UUID + extension), creating intermediate directories
  /// as needed.
  var importImage:
    @Sendable (
      _ sourceURL: URL,
      _ repositoryRootURL: URL
    ) throws -> String

  /// Removes a previously-imported image. No-op when the file is
  /// already gone (idempotent so reset/replace can call without
  /// guarding against stale state).
  var remove:
    @Sendable (
      _ filename: String,
      _ repositoryRootURL: URL
    ) throws -> Void

  /// Returns whether a previously-stored filename still resolves to an
  /// existing file. Renderers use this to decide whether to fall back.
  var exists:
    @Sendable (
      _ filename: String,
      _ repositoryRootURL: URL
    ) -> Bool
}

nonisolated enum RepositoryIconAssetStoreError: Error, Equatable {
  case unsupportedExtension(String)
}

nonisolated extension RepositoryIconAssetStore {
  /// Allowed input extensions. PNG and SVG only — JPEG and other
  /// formats either don't suit repo icon use (no transparency) or
  /// don't render well at small sidebar sizes.
  static let supportedExtensions: Set<String> = ["png", "svg"]

  static var liveValue: RepositoryIconAssetStore {
    RepositoryIconAssetStore(
      importImage: { sourceURL, rootURL in
        let normalizedExt = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(normalizedExt) else {
          throw RepositoryIconAssetStoreError.unsupportedExtension(normalizedExt)
        }
        let directory = SupacodePaths.repositoryIconsDirectory(for: rootURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString.lowercased()).\(normalizedExt)"
        let destination = directory.appending(path: filename, directoryHint: .notDirectory)
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destination, options: [.atomic])
        return filename
      },
      remove: { filename, rootURL in
        let url = SupacodePaths.repositoryIconFileURL(
          filename: filename, repositoryRootURL: rootURL
        )
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
          try FileManager.default.removeItem(at: url)
        }
      },
      exists: { filename, rootURL in
        let url = SupacodePaths.repositoryIconFileURL(
          filename: filename, repositoryRootURL: rootURL
        )
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }
    )
  }
}

nonisolated enum RepositoryIconAssetStoreKey: DependencyKey {
  static var liveValue: RepositoryIconAssetStore { .liveValue }
  static var previewValue: RepositoryIconAssetStore { .liveValue }
  static var testValue: RepositoryIconAssetStore { .liveValue }
}

extension DependencyValues {
  nonisolated var repositoryIconAssetStore: RepositoryIconAssetStore {
    get { self[RepositoryIconAssetStoreKey.self] }
    set { self[RepositoryIconAssetStoreKey.self] = newValue }
  }
}
