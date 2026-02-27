import Foundation
import Testing

@testable import supacode

struct RepositoryNameTests {
  @Test func usesParentDirectoryNameForBareRepositoryRoots() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha/.bare")

    #expect(Repository.name(for: root) == "repo-alpha")
  }

  @Test func preservesNormalRepositoryName() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha")

    #expect(Repository.name(for: root) == "repo-alpha")
  }
}

struct SupacodePathsTests {
  @Test func repositoryDirectoryUsesRepoNameForNormalRoots() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha")
    let directory = SupacodePaths.repositoryDirectory(for: root)

    #expect(directory.lastPathComponent == "repo-alpha")
  }

  @Test func repositoryDirectoryUsesSanitizedPathForBareRoots() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha/.bare")
    let directory = SupacodePaths.repositoryDirectory(for: root)

    #expect(directory.lastPathComponent == "tmp_work_repo-alpha_.bare")
  }

  @Test func repositoryDirectoryDoesNotCollideForDifferentBareRoots() {
    let firstRoot = URL(fileURLWithPath: "/tmp/work/repo-alpha/.bare")
    let secondRoot = URL(fileURLWithPath: "/tmp/work/repo-beta/.bare")

    let firstDirectory = SupacodePaths.repositoryDirectory(for: firstRoot)
    let secondDirectory = SupacodePaths.repositoryDirectory(for: secondRoot)

    #expect(firstDirectory != secondDirectory)
  }

  @Test func repositorySettingsURLUsesSupacodeRepoDirectory() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha")
    let settingsURL = SupacodePaths.repositorySettingsURL(for: root)

    #expect(settingsURL.lastPathComponent == "supacode.json")
    #expect(settingsURL.deletingLastPathComponent().lastPathComponent == "repo-alpha")
    #expect(settingsURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "repo")
  }

  @Test func onevcatRepositorySettingsURLUsesSupacodeRepoDirectory() {
    let root = URL(fileURLWithPath: "/tmp/work/repo-alpha/.bare")
    let settingsURL = SupacodePaths.onevcatRepositorySettingsURL(for: root)

    #expect(settingsURL.lastPathComponent == "supacode.onevcat.json")
    #expect(settingsURL.deletingLastPathComponent().lastPathComponent == ".bare")
    #expect(settingsURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "repo")
  }
}
