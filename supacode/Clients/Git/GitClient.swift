import Foundation
import Sentry

enum GitOperation: String {
  case repoRoot = "repo_root"
  case worktreeList = "worktree_list"
  case worktreeCreate = "worktree_create"
  case worktreeRemove = "worktree_remove"
  case branchNames = "branch_names"
  case branchRename = "branch_rename"
  case branchDelete = "branch_delete"
  case lineChanges = "line_changes"
  case remoteInfo = "remote_info"
}

enum GitClientError: LocalizedError {
  case commandFailed(command: String, message: String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let command, let message):
      if message.isEmpty {
        return "Git command failed: \(command)"
      }
      return "Git command failed: \(command)\n\(message)"
    }
  }
}

struct GitClient {
  private struct WorktreeSortEntry {
    let worktree: Worktree
    let createdAt: Date
    let index: Int
  }

  private let shell: ShellClient

  init(shell: ShellClient = .liveValue) {
    self.shell = shell
  }

  nonisolated func repoRoot(for path: URL) async throws -> URL {
    let normalizedPath = Self.directoryURL(for: path)
    let wtURL = try wtScriptURL()
    let output = try await runLoginShellProcess(
      operation: .repoRoot,
      executableURL: wtURL,
      arguments: ["root"],
      currentDirectoryURL: normalizedPath
    )
    if output.isEmpty {
      let command = "\(wtURL.lastPathComponent) root"
      throw GitClientError.commandFailed(command: command, message: "Empty output")
    }
    return URL(fileURLWithPath: output).standardizedFileURL
  }

  nonisolated func worktrees(for repoRoot: URL) async throws -> [Worktree] {
    let repositoryRootURL = repoRoot.standardizedFileURL
    let output = try await runWtList(repoRoot: repoRoot)
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return []
    }
    let data = Data(trimmed.utf8)
    let entries = try JSONDecoder().decode([GitWtWorktreeEntry].self, from: data)
    let worktreeEntries = entries.enumerated().map { index, entry in
      let worktreeURL = URL(fileURLWithPath: entry.path).standardizedFileURL
      let name = entry.branch.isEmpty ? worktreeURL.lastPathComponent : entry.branch
      let detail = Self.relativePath(from: repositoryRootURL, to: worktreeURL)
      let id = worktreeURL.path(percentEncoded: false)
      let resourceValues = try? worktreeURL.resourceValues(forKeys: [
        .creationDateKey, .contentModificationDateKey,
      ])
      let createdAt =
        resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? .distantPast
      return WorktreeSortEntry(
        worktree: Worktree(
          id: id,
          name: name,
          detail: detail,
          workingDirectory: worktreeURL,
          repositoryRootURL: repositoryRootURL
        ),
        createdAt: createdAt,
        index: index
      )
    }
    return
      worktreeEntries
      .sorted { lhs, rhs in
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt > rhs.createdAt
        }
        return lhs.index < rhs.index
      }
      .map(\.worktree)
  }

  nonisolated func localBranchNames(for repoRoot: URL) async throws -> Set<String> {
    let path = repoRoot.path(percentEncoded: false)
    let output = try await runGit(
      operation: .branchNames,
      arguments: [
        "-C",
        path,
        "for-each-ref",
        "--format=%(refname:short)",
        "refs/heads",
      ]
    )
    let names =
      output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    return Set(names)
  }

  nonisolated func createWorktree(
    named name: String,
    in repoRoot: URL,
    copyIgnored: Bool,
    copyUntracked: Bool
  ) async throws -> Worktree {
    let repositoryRootURL = repoRoot.standardizedFileURL
    let wtURL = try wtScriptURL()
    let baseDir = SupacodePaths.repositoryDirectory(for: repositoryRootURL)
    var arguments = ["--base-dir", baseDir.path(percentEncoded: false), "sw"]
    if copyIgnored {
      arguments.append("--copy-ignored")
    }
    if copyUntracked {
      arguments.append("--copy-untracked")
    }
    arguments.append(name)
    let output = try await runLoginShellProcess(
      operation: .worktreeCreate,
      executableURL: wtURL,
      arguments: arguments,
      currentDirectoryURL: repoRoot
    )
    let pathLine = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    if pathLine.isEmpty {
      let command = ([wtURL.lastPathComponent] + arguments).joined(separator: " ")
      throw GitClientError.commandFailed(command: command, message: "Empty output")
    }
    let worktreeURL = URL(fileURLWithPath: pathLine).standardizedFileURL
    let detail = Self.relativePath(from: repositoryRootURL, to: worktreeURL)
    let id = worktreeURL.path(percentEncoded: false)
    return Worktree(
      id: id,
      name: name,
      detail: detail,
      workingDirectory: worktreeURL,
      repositoryRootURL: repositoryRootURL
    )
  }

  nonisolated func renameBranch(in worktreeURL: URL, to branchName: String) async throws {
    let path = worktreeURL.path(percentEncoded: false)
    _ = try await runGit(
      operation: .branchRename,
      arguments: ["-C", path, "branch", "-m", branchName]
    )
  }

  nonisolated func branchName(for worktreeURL: URL) async -> String? {
    let headURL = await MainActor.run {
      GitWorktreeHeadResolver.headURL(
        for: worktreeURL,
        fileManager: .default
      )
    }
    guard let headURL else {
      return nil
    }
    guard
      let line = try? String(contentsOf: headURL, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .first
    else {
      return nil
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let refPrefix = "ref:"
    if trimmed.hasPrefix(refPrefix) {
      let ref = trimmed.dropFirst(refPrefix.count).trimmingCharacters(in: .whitespaces)
      let headsPrefix = "refs/heads/"
      if ref.hasPrefix(headsPrefix) {
        return String(ref.dropFirst(headsPrefix.count))
      }
      return String(ref)
    }
    return "HEAD"
  }

  nonisolated func lineChanges(at worktreeURL: URL) async -> (added: Int, removed: Int)? {
    let path = worktreeURL.path(percentEncoded: false)
    do {
      let diff = try await runGit(
        operation: .lineChanges,
        arguments: ["-C", path, "diff", "HEAD", "--numstat"]
      )
      let changes = parseNumstat(diff)
      return (added: changes.added, removed: changes.removed)
    } catch {
      return nil
    }
  }

  nonisolated func remoteInfo(for repositoryRoot: URL) async -> GithubRemoteInfo? {
    let path = repositoryRoot.path(percentEncoded: false)
    guard
      let remotesOutput = try? await runGit(
        operation: .remoteInfo,
        arguments: ["-C", path, "remote"]
      )
    else {
      return nil
    }
    let remotes = remotesOutput
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let orderedRemotes: [String]
    if remotes.contains("origin") {
      orderedRemotes = ["origin"] + remotes.filter { $0 != "origin" }
    } else {
      orderedRemotes = remotes
    }
    for remote in orderedRemotes {
      guard
        let remoteURL = try? await runGit(
          operation: .remoteInfo,
          arguments: ["-C", path, "remote", "get-url", remote]
        )
      else {
        continue
      }
      if let info = Self.parseGithubRemoteInfo(remoteURL) {
        return info
      }
    }
    return nil
  }

  nonisolated func removeWorktree(_ worktree: Worktree) async throws -> URL {
    let rootPath = worktree.repositoryRootURL.path(percentEncoded: false)
    let worktreePath = worktree.workingDirectory.path(percentEncoded: false)
    _ = try await runGit(
      operation: .worktreeRemove,
      arguments: [
        "-C",
        rootPath,
        "worktree",
        "remove",
        "--force",
        worktreePath,
      ]
    )
    if !worktree.name.isEmpty {
      let names = try await localBranchNames(for: worktree.repositoryRootURL)
      if names.contains(worktree.name.lowercased()) {
        _ = try await runGit(
          operation: .branchDelete,
          arguments: ["-C", rootPath, "branch", "-D", worktree.name]
        )
      }
    }
    return worktree.workingDirectory
  }

  nonisolated private func parseNumstat(_ output: String) -> (added: Int, removed: Int) {
    output
      .split(whereSeparator: \.isNewline)
      .reduce(into: (added: 0, removed: 0)) { result, line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return }
        let added = Int(parts[0]) ?? 0
        let removed = Int(parts[1]) ?? 0
        result.added += added
        result.removed += removed
      }
  }

  nonisolated private func runGit(
    operation: GitOperation,
    arguments: [String]
  ) async throws -> String {
    let env = URL(fileURLWithPath: "/usr/bin/env")
    let command = ([env.path(percentEncoded: false)] + ["git"] + arguments).joined(separator: " ")
    do {
      return try await shell.run(env, ["git"] + arguments, nil).stdout
    } catch {
      throw wrapShellError(error, operation: operation, command: command)
    }
  }

  nonisolated private func runWtList(repoRoot: URL) async throws -> String {
    let wtURL = try wtScriptURL()
    let arguments = ["ls", "--json"]
    print(
      "\(wtURL.lastPathComponent) \(arguments.joined(separator: " "))"
    )
    let output = try await runLoginShellProcess(
      operation: .worktreeList,
      executableURL: wtURL,
      arguments: arguments,
      currentDirectoryURL: repoRoot
    )
    print(output)
    print()
    return output
  }

  nonisolated private func wtScriptURL() throws -> URL {
    guard let url = Bundle.main.url(forResource: "wt", withExtension: nil, subdirectory: "git-wt") else {
      fatalError("Bundled wt script not found")
    }
    return url
  }

  nonisolated private func runLoginShellProcess(
    operation: GitOperation,
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL?
  ) async throws -> String {
    let command = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")
    do {
      return try await shell.runLogin(executableURL, arguments, currentDirectoryURL).stdout
    } catch {
      throw wrapShellError(error, operation: operation, command: command)
    }
  }

  nonisolated private static func relativePath(from base: URL, to target: URL) -> String {
    let baseComponents = base.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var index = 0
    while index < min(baseComponents.count, targetComponents.count),
      baseComponents[index] == targetComponents[index]
    {
      index += 1
    }
    var result: [String] = []
    if index < baseComponents.count {
      result.append(contentsOf: Array(repeating: "..", count: baseComponents.count - index))
    }
    if index < targetComponents.count {
      result.append(contentsOf: targetComponents[index...])
    }
    if result.isEmpty {
      return "."
    }
    return result.joined(separator: "/")
  }

  nonisolated private static func directoryURL(for path: URL) -> URL {
    if path.hasDirectoryPath {
      return path
    }
    return path.deletingLastPathComponent()
  }

  nonisolated static func parseGithubRemoteInfo(_ remoteURL: String) -> GithubRemoteInfo? {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    if trimmed.hasPrefix("git@") {
      let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
      guard parts.count == 2 else {
        return nil
      }
      let hostAndPath = parts[1]
      let hostParts = hostAndPath.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
      guard hostParts.count == 2 else {
        return nil
      }
      return parseGithubRemoteInfo(host: String(hostParts[0]), path: String(hostParts[1]))
    }
    guard let url = URL(string: trimmed), let host = url.host else {
      return nil
    }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return parseGithubRemoteInfo(host: host, path: path)
  }

  nonisolated private static func parseGithubRemoteInfo(host: String, path: String) -> GithubRemoteInfo? {
    let normalizedHost = host.lowercased()
    guard normalizedHost.contains("github") else {
      return nil
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count >= 2 else {
      return nil
    }
    let owner = String(components[0])
    var repo = String(components[1])
    if repo.hasSuffix(".git") {
      repo = String(repo.dropLast(4))
    }
    guard !owner.isEmpty, !repo.isEmpty else {
      return nil
    }
    return GithubRemoteInfo(host: host, owner: owner, repo: repo)
  }

}

nonisolated private func wrapShellError(
  _ error: Error,
  operation: GitOperation,
  command: String
) -> GitClientError {
  let gitError: GitClientError
  var exitCode: Int32 = -1
  if let shellError = error as? ShellClientError {
    exitCode = shellError.exitCode
    var messageParts: [String] = []
    if !shellError.stdout.isEmpty {
      messageParts.append("stdout:\n\(shellError.stdout)")
    }
    if !shellError.stderr.isEmpty {
      messageParts.append("stderr:\n\(shellError.stderr)")
    }
    let message = messageParts.joined(separator: "\n")
    gitError = .commandFailed(command: command, message: message)
  } else {
    gitError = .commandFailed(command: command, message: error.localizedDescription)
  }
  #if !DEBUG
    SentrySDK.logger.error(
      "git command failed",
      attributes: [
        "operation": operation.rawValue,
        "exit_code": Int(exitCode),
      ]
    )
  #endif
  return gitError
}

struct GitWtWorktreeEntry: Decodable {
  let branch: String
  let path: String
  let head: String
}
