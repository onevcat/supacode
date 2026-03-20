import Foundation
import Testing

@testable import supacode

nonisolated final class GitWorktreeDiscoveryRecorder: @unchecked Sendable {
  struct Invocation: Equatable {
    let executablePath: String
    let arguments: [String]
    let currentDirectoryPath: String?
  }

  private let lock = NSLock()
  private var runInvocationsValue: [Invocation] = []
  private var loginInvocationsValue: [Invocation] = []

  func recordRun(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) {
    lock.lock()
    runInvocationsValue.append(
      Invocation(
        executablePath: executableURL.path(percentEncoded: false),
        arguments: arguments,
        currentDirectoryPath: currentDirectoryURL?.path(percentEncoded: false)
      )
    )
    lock.unlock()
  }

  func recordLogin(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) {
    lock.lock()
    loginInvocationsValue.append(
      Invocation(
        executablePath: executableURL.path(percentEncoded: false),
        arguments: arguments,
        currentDirectoryPath: currentDirectoryURL?.path(percentEncoded: false)
      )
    )
    lock.unlock()
  }

  func runInvocations() -> [Invocation] {
    lock.lock()
    let value = runInvocationsValue
    lock.unlock()
    return value
  }

  func loginInvocations() -> [Invocation] {
    lock.lock()
    let value = loginInvocationsValue
    lock.unlock()
    return value
  }
}

struct GitClientWorktreeDiscoveryTests {
  @Test func repoRootUsesDirectBundledWtExecution() async throws {
    let recorder = GitWorktreeDiscoveryRecorder()
    let shell = ShellClient(
      run: { executableURL, arguments, currentDirectoryURL in
        recorder.recordRun(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        return ShellOutput(stdout: "/tmp/repo\n", stderr: "", exitCode: 0)
      },
      runLoginImpl: { executableURL, arguments, currentDirectoryURL, _ in
        recorder.recordLogin(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        Issue.record("repoRoot should not use runLogin when direct execution succeeds")
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )
    let client = GitClient(shell: shell)
    let worktreeURL = URL(fileURLWithPath: "/tmp/repo/worktree")

    let root = try await client.repoRoot(for: worktreeURL)

    #expect(root.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "tmp/repo")
    let runs = recorder.runInvocations()
    #expect(runs.count == 1)
    if let invocation = runs.first {
      #expect(invocation.arguments == ["root"])
      let normalizedPath = URL(fileURLWithPath: invocation.currentDirectoryPath ?? "")
        .standardizedFileURL
        .path(percentEncoded: false)
      #expect(normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "tmp/repo")
    } else {
      Issue.record("Expected one direct bundled wt invocation for repoRoot")
    }
    #expect(recorder.loginInvocations().isEmpty)
  }

  @Test func worktreesUseDirectBundledWtExecution() async throws {
    let recorder = GitWorktreeDiscoveryRecorder()
    let output = """
      [
        {"branch":"main","path":"/tmp/repo","head":"abc","is_bare":false},
        {"branch":"feature","path":"/tmp/repo/.worktrees/feature","head":"def","is_bare":false}
      ]
      """
    let shell = ShellClient(
      run: { executableURL, arguments, currentDirectoryURL in
        recorder.recordRun(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        return ShellOutput(stdout: output, stderr: "", exitCode: 0)
      },
      runLoginImpl: { executableURL, arguments, currentDirectoryURL, _ in
        recorder.recordLogin(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        Issue.record("worktrees should not use runLogin when direct execution succeeds")
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )
    let client = GitClient(shell: shell)
    let repoRoot = URL(fileURLWithPath: "/tmp/repo")

    let worktrees = try await client.worktrees(for: repoRoot)

    #expect(worktrees.map(\.id) == ["/tmp/repo", "/tmp/repo/.worktrees/feature"])
    let runs = recorder.runInvocations()
    #expect(runs.count == 1)
    if let invocation = runs.first {
      #expect(invocation.arguments == ["ls", "--json"])
      #expect(invocation.currentDirectoryPath == "/tmp/repo")
    } else {
      Issue.record("Expected one direct bundled wt invocation for worktree discovery")
    }
    #expect(recorder.loginInvocations().isEmpty)
  }

  @Test func worktreesFallbackToLoginShellWhenDirectExecutionCannotResolveGit() async throws {
    let recorder = GitWorktreeDiscoveryRecorder()
    let shell = ShellClient(
      run: { executableURL, arguments, currentDirectoryURL in
        recorder.recordRun(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        throw ShellClientError(
          command: "wt ls --json",
          stdout: "",
          stderr: "git: command not found",
          exitCode: 127
        )
      },
      runLoginImpl: { executableURL, arguments, currentDirectoryURL, _ in
        recorder.recordLogin(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
        return ShellOutput(
          stdout: #"[{"branch":"main","path":"/tmp/repo","head":"abc","is_bare":false}]"#,
          stderr: "",
          exitCode: 0
        )
      }
    )
    let client = GitClient(shell: shell)
    let repoRoot = URL(fileURLWithPath: "/tmp/repo")

    let worktrees = try await client.worktrees(for: repoRoot)

    #expect(worktrees.map(\.id) == ["/tmp/repo"])
    #expect(recorder.runInvocations().count == 1)
    #expect(recorder.loginInvocations().count == 1)
    if let invocation = recorder.loginInvocations().first {
      #expect(invocation.arguments == ["ls", "--json"])
    } else {
      Issue.record("Expected login-shell fallback invocation for worktree discovery")
    }
  }
}
