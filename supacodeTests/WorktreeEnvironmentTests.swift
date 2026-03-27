import Foundation
import Testing

@testable import supacode

@MainActor
struct WorktreeEnvironmentTests {
  @Test func scriptEnvironmentContainsExpectedKeys() {
    let worktree = Worktree(
      id: "/tmp/repo/wt-1",
      name: "feature-branch",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
    )
    let env = worktree.scriptEnvironment
    #expect(env["SUPACODE_WORKTREE_PATH"] == "/tmp/repo/wt-1")
    #expect(env["SUPACODE_ROOT_PATH"] == "/tmp/repo")
    #expect(env.count == 2)
  }

  @Test func exportPrefixFormatsCorrectly() {
    let worktree = Worktree(
      id: "/tmp/repo/wt-1",
      name: "feature-branch",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo/.bare"),
    )
    let exports = worktree.scriptEnvironmentExportPrefix
    #expect(exports.contains("export SUPACODE_WORKTREE_PATH='/tmp/repo/wt-1'"))
    #expect(exports.contains("export SUPACODE_ROOT_PATH='/tmp/repo/.bare'"))
    #expect(exports.hasSuffix("\n"))
  }

  @Test func exportPrefixIsSortedByKey() {
    let worktree = Worktree(
      id: "/tmp/repo/wt-1",
      name: "feature-branch",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo/.bare"),
    )
    let lines = worktree.scriptEnvironmentExportPrefix
      .trimmingCharacters(in: .newlines)
      .components(separatedBy: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].contains("SUPACODE_ROOT_PATH"))
    #expect(lines[1].contains("SUPACODE_WORKTREE_PATH"))
  }

  @Test func exportPrefixQuotesPathsWithSpaces() {
    let worktree = Worktree(
      id: "/tmp/my repo/wt 1",
      name: "feature-branch",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/my repo/wt 1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/my repo/.bare"),
    )
    let exports = worktree.scriptEnvironmentExportPrefix
    #expect(exports.contains("export SUPACODE_WORKTREE_PATH='/tmp/my repo/wt 1'"))
    #expect(exports.contains("export SUPACODE_ROOT_PATH='/tmp/my repo/.bare'"))
  }
}
