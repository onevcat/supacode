import Foundation
import Testing

@testable import supacode

@MainActor
struct RepositoryIconAssetStoreTests {
  // MARK: - Helpers

  private static func makeTempRepoRoot() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "prowl-icon-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func writeSourceFile(extension ext: String, contents: Data = Data([0xDE, 0xAD]))
    throws
    -> URL
  {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "prowl-icon-source-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: "icon.\(ext)", directoryHint: .notDirectory)
    try contents.write(to: url)
    return url
  }

  // MARK: - importImage

  @Test func importImageCopiesFileWithUUIDName() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "png", contents: Data([0x01, 0x02, 0x03]))

    let filename = try store.importImage(source, repoRoot)

    #expect(filename.hasSuffix(".png"))
    #expect(UUID(uuidString: String(filename.dropLast(4))) != nil)

    let resolved = SupacodePaths.repositoryIconFileURL(
      filename: filename, repositoryRootURL: repoRoot
    )
    let copied = try Data(contentsOf: resolved)
    #expect(copied == Data([0x01, 0x02, 0x03]))
  }

  @Test func importImageNormalizesUppercaseExtension() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "PNG")

    let filename = try store.importImage(source, repoRoot)
    #expect(filename.hasSuffix(".png"))
  }

  @Test func importImageAcceptsSVG() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "svg")

    let filename = try store.importImage(source, repoRoot)
    #expect(filename.hasSuffix(".svg"))
  }

  @Test func importImageRejectsUnsupportedExtension() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "jpeg")

    #expect(throws: RepositoryIconAssetStoreError.self) {
      _ = try store.importImage(source, repoRoot)
    }
  }

  @Test func importImageCreatesIconsDirectoryWhenMissing() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    // Don't pre-create the icons directory — importImage should make
    // it itself, otherwise first-time imports would fail.
    let source = try Self.writeSourceFile(extension: "png")

    _ = try store.importImage(source, repoRoot)

    let iconsDir = SupacodePaths.repositoryIconsDirectory(for: repoRoot)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: iconsDir.path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(exists)
    #expect(isDirectory.boolValue)
  }

  @Test func importImageGeneratesUniqueFilenamePerCall() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "png")

    let first = try store.importImage(source, repoRoot)
    let second = try store.importImage(source, repoRoot)
    #expect(first != second)
  }

  // MARK: - exists

  @Test func existsReportsFalseWhenMissing() {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    #expect(!store.exists("nonexistent.png", repoRoot))
  }

  @Test func existsReportsTrueAfterImport() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "png")
    let filename = try store.importImage(source, repoRoot)
    #expect(store.exists(filename, repoRoot))
  }

  // MARK: - remove

  @Test func removeDeletesImportedFile() throws {
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    let source = try Self.writeSourceFile(extension: "png")
    let filename = try store.importImage(source, repoRoot)

    try store.remove(filename, repoRoot)
    #expect(!store.exists(filename, repoRoot))
  }

  @Test func removeIsIdempotent() throws {
    // Reset / replace flows can call remove repeatedly; missing files
    // shouldn't throw or the reducer would have to track existence.
    let store = RepositoryIconAssetStore.liveValue
    let repoRoot = Self.makeTempRepoRoot()
    try store.remove("never-existed.png", repoRoot)
  }
}
