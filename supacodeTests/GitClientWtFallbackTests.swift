import Foundation
import Testing

@testable import supacode

nonisolated private func normalizedPath(_ path: String) -> String {
  guard path.count > 1, path.hasSuffix("/") else {
    return path
  }
  return String(path.dropLast())
}

actor GitFallbackShellCallStore {
  private(set) var runCalls: [[String]] = []
  private(set) var runLoginCalls: [[String]] = []

  func recordRun(_ arguments: [String]) {
    runCalls.append(arguments)
  }

  func recordRunLogin(_ arguments: [String]) {
    runLoginCalls.append(arguments)
  }
}

struct GitClientWtFallbackTests {
  @Test func repoRootFallsBackToGitCommonDirectoryWhenWtScriptIsMissing() async throws {
    let store = GitFallbackShellCallStore()
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.recordRun(arguments)
        if arguments.contains("--git-common-dir") {
          return ShellOutput(stdout: "/tmp/repo/.git\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, arguments, _, _ in
        await store.recordRunLogin(arguments)
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )
    let client = GitClient(shell: shell, bundledWtScriptURLProvider: { nil })

    let resolved = try await client.repoRoot(for: URL(fileURLWithPath: "/tmp/repo/worktree-a"))

    #expect(
      normalizedPath(resolved.path(percentEncoded: false))
        == normalizedPath(URL(fileURLWithPath: "/tmp/repo").standardizedFileURL.path(percentEncoded: false))
    )
    let runCalls = await store.runCalls
    #expect(runCalls.count == 1)
    #expect(runCalls[0].contains("--git-common-dir"))
    #expect(runCalls[0].contains("--path-format=absolute"))
    let runLoginCalls = await store.runLoginCalls
    #expect(runLoginCalls.isEmpty)
  }

  @Test func worktreesFallsBackToGitWorktreeListWhenWtScriptIsMissing() async throws {
    let store = GitFallbackShellCallStore()
    let porcelain = """
      worktree /tmp/repo
      HEAD aaa111
      branch refs/heads/main

      worktree /tmp/repo/feature-a
      HEAD bbb222
      branch refs/heads/feature-a

      worktree /tmp/repo.git
      bare
      HEAD ccc333
      """
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.recordRun(arguments)
        return ShellOutput(stdout: porcelain, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, arguments, _, _ in
        await store.recordRunLogin(arguments)
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )
    let client = GitClient(shell: shell, bundledWtScriptURLProvider: { nil })

    let worktrees = try await client.worktrees(for: URL(fileURLWithPath: "/tmp/repo"))

    #expect(worktrees.map(\.id) == ["/tmp/repo", "/tmp/repo/feature-a"])
    #expect(worktrees.map(\.name) == ["main", "feature-a"])
    #expect(worktrees.map(\.detail) == [".", "feature-a"])
    let runCalls = await store.runCalls
    #expect(runCalls.count == 1)
    #expect(runCalls[0].contains("worktree"))
    #expect(runCalls[0].contains("list"))
    #expect(runCalls[0].contains("--porcelain"))
    let runLoginCalls = await store.runLoginCalls
    #expect(runLoginCalls.isEmpty)
  }

  @Test func createWorktreeThrowsRecoverableErrorWhenWtScriptIsMissing() async {
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell, bundledWtScriptURLProvider: { nil })

    do {
      _ = try await client.createWorktree(
        named: "swift-otter",
        in: URL(fileURLWithPath: "/tmp/repo"),
        copyIgnored: false,
        copyUntracked: false,
        baseRef: ""
      )
      Issue.record("Expected createWorktree to throw when bundled wt script is missing")
    } catch let error as GitClientError {
      #expect(error.localizedDescription.contains("Bundled wt script not found"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
