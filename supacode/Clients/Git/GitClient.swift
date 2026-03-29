import Foundation
import Sentry

enum GitOperation: String {
  case repoRoot = "repo_root"
  case worktreeList = "worktree_list"
  case worktreeCreate = "worktree_create"
  case worktreeRemove = "worktree_remove"
  case worktreePrune = "worktree_prune"
  case repoIsBare = "repo_is_bare"
  case branchNames = "branch_names"
  case branchNameValidation = "branch_name_validation"
  case branchRefs = "branch_refs"
  case defaultRemoteBranchRef = "default_remote_branch_ref"
  case localHeadRef = "local_head_ref"
  case ignoredFileCount = "ignored_file_count"
  case untrackedFileCount = "untracked_file_count"
  case branchRename = "branch_rename"
  case branchDelete = "branch_delete"
  case lineChanges = "line_changes"
  case diffNameStatus = "diff_name_status"
  case untrackedFilePaths = "untracked_file_paths"
  case showFile = "show_file"
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

enum GitWorktreeCreateEvent: Equatable, Sendable {
  case outputLine(ShellStreamLine)
  case finished(Worktree)
}

struct GitClient {
  private struct WorktreeSortEntry {
    let worktree: Worktree
    let createdAt: Date
    let index: Int
  }

  private let shell: ShellClient
  private let remoteExecution: RemoteExecutionClient

  nonisolated init(shell: ShellClient = .live) {
    self.init(
      shell: shell,
      remoteExecution: makeDefaultRemoteExecutionClient(shell: shell)
    )
  }

  nonisolated init(
    shell: ShellClient,
    remoteExecution: RemoteExecutionClient
  ) {
    self.shell = shell
    self.remoteExecution = remoteExecution
  }

  nonisolated func repoRoot(for path: URL) async throws -> URL {
    let normalizedPath = Self.directoryURL(for: path)
    let wtURL = try wtScriptURL()
    let output = try await runBundledWtProcess(
      operation: .repoRoot,
      executableURL: wtURL,
      arguments: ["root"],
      currentDirectoryURL: normalizedPath
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      let command = "\(wtURL.lastPathComponent) root"
      throw GitClientError.commandFailed(command: command, message: "Empty output")
    }
    return URL(fileURLWithPath: trimmed).standardizedFileURL
  }

  nonisolated func worktrees(for repoRoot: URL) async throws -> [Worktree] {
    try await worktrees(
      for: repoRoot,
      endpoint: .local,
      hostProfile: nil
    )
  }

  nonisolated func worktrees(
    for repoRoot: URL,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) async throws -> [Worktree] {
    switch endpoint {
    case .local:
      return try await localWorktrees(for: repoRoot)
    case .remote(_, let remotePath):
      return try await remoteWorktrees(
        for: repoRoot,
        remotePath: remotePath,
        endpoint: endpoint,
        hostProfile: hostProfile
      )
    }
  }

  nonisolated private func localWorktrees(for repoRoot: URL) async throws -> [Worktree] {
    let output = try await runWtList(repoRoot: repoRoot)
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return []
    }
    let data = Data(trimmed.utf8)
    let entries = try JSONDecoder().decode([GitWtWorktreeEntry].self, from: data)
      .filter { !$0.isBare }
    return worktrees(
      from: entries,
      repositoryRootURL: repoRoot.standardizedFileURL,
      detailBaseURL: repoRoot.standardizedFileURL,
      endpoint: .local,
      includeCreationDates: true
    )
  }

  nonisolated private func remoteWorktrees(
    for repoRoot: URL,
    remotePath: String,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) async throws -> [Worktree] {
    let command = buildRemoteGitCommand(
      remotePath: remotePath,
      arguments: ["worktree", "list", "--porcelain"]
    )
    let output = try await runRemoteGit(
      operation: .worktreeList,
      command: command,
      hostProfile: hostProfile,
      timeoutSeconds: remoteGitTimeoutSeconds
    )
    let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return []
    }
    let entries = parseRemoteWorktreeEntries(trimmed).filter { !$0.isBare }
    return worktrees(
      from: entries,
      repositoryRootURL: repoRoot.standardizedFileURL,
      detailBaseURL: URL(fileURLWithPath: remotePath).standardizedFileURL,
      endpoint: endpoint,
      includeCreationDates: false
    )
  }

  nonisolated func pruneWorktrees(for repoRoot: URL) async throws {
    let path = repoRoot.path(percentEncoded: false)
    _ = try await runGit(
      operation: .worktreePrune,
      arguments: ["-C", path, "worktree", "prune"]
    )
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

  nonisolated func isValidBranchName(_ branchName: String, for repoRoot: URL) async -> Bool {
    let path = repoRoot.path(percentEncoded: false)
    do {
      _ = try await runGit(
        operation: .branchNameValidation,
        arguments: ["-C", path, "check-ref-format", "--branch", branchName]
      )
      return true
    } catch {
      return false
    }
  }

  nonisolated func isBareRepository(for repoRoot: URL) async throws -> Bool {
    let path = repoRoot.path(percentEncoded: false)
    let output = try await runGit(
      operation: .repoIsBare,
      arguments: ["-C", path, "rev-parse", "--is-bare-repository"]
    )
    return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
  }

  nonisolated func branchRefs(for repoRoot: URL) async throws -> [String] {
    let path = repoRoot.path(percentEncoded: false)
    let localOutput = try await runGit(
      operation: .branchRefs,
      arguments: [
        "-C",
        path,
        "for-each-ref",
        "--format=%(refname:short)\t%(upstream:short)",
        "refs/heads",
      ]
    )
    let refs = parseLocalRefsWithUpstream(localOutput)
      .filter { !$0.hasSuffix("/HEAD") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return deduplicated(refs)
  }

  nonisolated func defaultRemoteBranchRef(for repoRoot: URL) async throws -> String? {
    let path = repoRoot.path(percentEncoded: false)
    do {
      let output = try await runGit(
        operation: .defaultRemoteBranchRef,
        arguments: ["-C", path, "symbolic-ref", "-q", "refs/remotes/origin/HEAD"]
      )
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      if let resolved = normalizeRemoteRef(trimmed),
        await refExists(resolved, repoRoot: repoRoot)
      {
        return resolved
      }
    } catch {
      let rootPath = repoRoot.path(percentEncoded: false)
      gitLogger.warning(
        "Default remote branch ref failed for \(rootPath): \(error.localizedDescription)"
      )
    }
    let fallback = "origin/main"
    if await refExists(fallback, repoRoot: repoRoot) {
      return fallback
    }
    return nil
  }

  nonisolated func automaticWorktreeBaseRef(for repoRoot: URL) async -> String? {
    let resolved = try? await defaultRemoteBranchRef(for: repoRoot)
    if let resolved {
      return Self.preferredBaseRef(remote: resolved, localHead: nil)
    }
    let localHead = try? await localHeadBranchRef(for: repoRoot)
    let resolvedLocalHead = await resolveLocalHead(localHead, repoRoot: repoRoot)
    return Self.preferredBaseRef(remote: nil, localHead: resolvedLocalHead)
  }

  nonisolated func ignoredFileCount(for repoRoot: URL) async throws -> Int {
    let path = repoRoot.path(percentEncoded: false)
    let output = try await runGit(
      operation: .ignoredFileCount,
      arguments: ["-C", path, "ls-files", "--others", "-i", "--exclude-standard"]
    )
    return parseFileListCount(output)
  }

  nonisolated func untrackedFileCount(for repoRoot: URL) async throws -> Int {
    let path = repoRoot.path(percentEncoded: false)
    let output = try await runGit(
      operation: .untrackedFileCount,
      arguments: ["-C", path, "ls-files", "--others", "--exclude-standard"]
    )
    return parseFileListCount(output)
  }

  nonisolated func createWorktree(
    named name: String,
    in repoRoot: URL,
    baseDirectory: URL,
    copyFiles: (ignored: Bool, untracked: Bool),
    baseRef: String
  ) async throws -> Worktree {
    try await createWorktree(
      named: name,
      in: repoRoot,
      baseDirectory: baseDirectory,
      copyFiles: copyFiles,
      baseRef: baseRef,
      endpoint: .local,
      hostProfile: nil
    )
  }

  nonisolated func createWorktree(
    named name: String,
    in repoRoot: URL,
    baseDirectory: URL,
    copyFiles: (ignored: Bool, untracked: Bool),
    baseRef: String,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) async throws -> Worktree {
    var createdWorktree: Worktree?
    for try await event in createWorktreeStream(
      named: name,
      in: repoRoot,
      baseDirectory: baseDirectory,
      copyFiles: copyFiles,
      baseRef: baseRef,
      endpoint: endpoint,
      hostProfile: hostProfile
    ) {
      if case .finished(let worktree) = event {
        createdWorktree = worktree
      }
    }
    guard let createdWorktree else {
      let wtURL = try wtScriptURL()
      let command =
        ([wtURL.lastPathComponent]
        + createWorktreeArguments(
          baseDirectory: baseDirectory,
          name: name,
          copyIgnored: copyFiles.ignored,
          copyUntracked: copyFiles.untracked,
          baseRef: baseRef
        )).joined(separator: " ")
      throw GitClientError.commandFailed(command: command, message: "Empty output")
    }
    return createdWorktree
  }

  nonisolated func createWorktreeStream(
    named name: String,
    in repoRoot: URL,
    baseDirectory: URL,
    copyFiles: (ignored: Bool, untracked: Bool),
    baseRef: String
  ) -> AsyncThrowingStream<GitWorktreeCreateEvent, Error> {
    createWorktreeStream(
      named: name,
      in: repoRoot,
      baseDirectory: baseDirectory,
      copyFiles: copyFiles,
      baseRef: baseRef,
      endpoint: .local,
      hostProfile: nil
    )
  }

  nonisolated func createWorktreeStream(
    named name: String,
    in repoRoot: URL,
    baseDirectory: URL,
    copyFiles: (ignored: Bool, untracked: Bool),
    baseRef: String,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) -> AsyncThrowingStream<GitWorktreeCreateEvent, Error> {
    switch endpoint {
    case .local:
      return localCreateWorktreeStream(
        named: name,
        in: repoRoot,
        baseDirectory: baseDirectory,
        copyFiles: copyFiles,
        baseRef: baseRef
      )
    case .remote(_, let remotePath):
      return remoteCreateWorktreeStream(
        named: name,
        in: repoRoot,
        remotePath: remotePath,
        baseDirectory: baseDirectory,
        baseRef: baseRef,
        endpoint: endpoint,
        hostProfile: hostProfile
      )
    }
  }

  nonisolated private func localCreateWorktreeStream(
    named name: String,
    in repoRoot: URL,
    baseDirectory: URL,
    copyFiles: (ignored: Bool, untracked: Bool),
    baseRef: String
  ) -> AsyncThrowingStream<GitWorktreeCreateEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let repositoryRootURL = repoRoot.standardizedFileURL
        do {
          let wtURL = try wtScriptURL()
          let arguments = createWorktreeArguments(
            baseDirectory: baseDirectory,
            name: name,
            copyIgnored: copyFiles.ignored,
            copyUntracked: copyFiles.untracked,
            baseRef: baseRef
          )
          let envURL = URL(fileURLWithPath: "/usr/bin/env")
          let localeArguments = ["LANG=C", "LC_ALL=C", "LC_MESSAGES=C"]
          let invocationArguments = localeArguments + [wtURL.path(percentEncoded: false)] + arguments
          let command = ([envURL.path(percentEncoded: false)] + invocationArguments).joined(separator: " ")
          var pathLine: String?
          do {
            for try await streamEvent in shell.runLoginStream(
              envURL,
              invocationArguments,
              repoRoot
            ) {
              switch streamEvent {
              case .line(let line):
                continuation.yield(.outputLine(line))
                if line.source == .stdout {
                  let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                  if !trimmed.isEmpty {
                    pathLine = trimmed
                  }
                }
              case .finished(let output):
                if pathLine == nil {
                  pathLine = lastNonEmptyLine(in: output.stdout)
                }
                guard let pathLine else {
                  throw GitClientError.commandFailed(command: command, message: "Empty output")
                }
                let worktreeURL = URL(fileURLWithPath: pathLine).standardizedFileURL
                let detail = Self.relativePath(from: repositoryRootURL, to: worktreeURL)
                let id = worktreeURL.path(percentEncoded: false)
                let resourceValues = try? worktreeURL.resourceValues(forKeys: [
                  .creationDateKey, .contentModificationDateKey,
                ])
                let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate
                let worktree = Worktree(
                  id: id,
                  name: name,
                  detail: detail,
                  workingDirectory: worktreeURL,
                  repositoryRootURL: repositoryRootURL,
                  createdAt: createdAt
                )
                continuation.yield(.finished(worktree))
                continuation.finish()
                return
              }
            }
            continuation.finish(throwing: GitClientError.commandFailed(command: command, message: "Empty output"))
          } catch {
            if let gitError = error as? GitClientError {
              continuation.finish(throwing: gitError)
            } else {
              continuation.finish(
                throwing: wrapShellError(error, operation: .worktreeCreate, command: command)
              )
            }
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  nonisolated private func remoteCreateWorktreeStream(
    named name: String,
    in repoRoot: URL,
    remotePath: String,
    baseDirectory: URL,
    baseRef: String,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) -> AsyncThrowingStream<GitWorktreeCreateEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let repositoryRootURL = repoRoot.standardizedFileURL
        let remoteRepositoryRootURL = URL(fileURLWithPath: remotePath).standardizedFileURL
        let worktreeURL = baseDirectory
          .appending(path: name, directoryHint: .isDirectory)
          .standardizedFileURL
        let worktreePath = worktreeURL.path(percentEncoded: false)
        let command = buildRemoteCreateWorktreeCommand(
          remotePath: remotePath,
          worktreePath: worktreePath,
          name: name,
          baseRef: baseRef
        )
        do {
          let output = try await runRemoteGit(
            operation: .worktreeCreate,
            command: command,
            hostProfile: hostProfile,
            timeoutSeconds: remoteGitCreateTimeoutSeconds
          )
          for line in output.stderr.split(whereSeparator: \.isNewline) {
            continuation.yield(.outputLine(ShellStreamLine(source: .stderr, text: String(line))))
          }
          for line in output.stdout.split(whereSeparator: \.isNewline) {
            continuation.yield(.outputLine(ShellStreamLine(source: .stdout, text: String(line))))
          }
          let detail = Self.relativePath(from: remoteRepositoryRootURL, to: worktreeURL)
          continuation.yield(
            .finished(
              Worktree(
                id: worktreePath,
                name: name,
                detail: detail,
                workingDirectory: worktreeURL,
                repositoryRootURL: repositoryRootURL,
                endpoint: endpoint
              )
            )
          )
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  nonisolated private func createWorktreeArguments(
    baseDirectory: URL,
    name: String,
    copyIgnored: Bool,
    copyUntracked: Bool,
    baseRef: String
  ) -> [String] {
    var arguments = ["--base-dir", baseDirectory.path(percentEncoded: false), "sw"]
    if copyIgnored {
      arguments.append("--copy-ignored")
    }
    if copyUntracked {
      arguments.append("--copy-untracked")
    }
    if !baseRef.isEmpty {
      arguments.append("--from")
      arguments.append(baseRef)
    }
    if copyIgnored || copyUntracked {
      arguments.append("--verbose")
    }
    arguments.append(name)
    return arguments
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
    if await isWorktreeIndexLocked(worktreeURL) {
      return nil
    }
    let path = worktreeURL.path(percentEncoded: false)
    do {
      let diff = try await runGit(
        operation: .lineChanges,
        arguments: ["-C", path, "diff", "HEAD", "--shortstat"]
      )
      let changes = parseShortstat(diff)
      return (added: changes.added, removed: changes.removed)
    } catch {
      return nil
    }
  }

  nonisolated private func isWorktreeIndexLocked(_ worktreeURL: URL) async -> Bool {
    let headURL = await MainActor.run {
      GitWorktreeHeadResolver.headURL(
        for: worktreeURL,
        fileManager: .default
      )
    }
    guard let headURL else {
      return false
    }
    let gitDirectory = headURL.deletingLastPathComponent()
    let lockURL = gitDirectory.appending(path: "index.lock")
    return FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false))
  }

  nonisolated func diffNameStatus(at worktreeURL: URL) async -> String {
    let path = worktreeURL.path(percentEncoded: false)
    do {
      return try await runGit(
        operation: .diffNameStatus,
        arguments: ["-C", path, "-c", "core.quotePath=false", "diff", "HEAD", "--name-status"]
      )
    } catch {
      return ""
    }
  }

  nonisolated func untrackedFilePaths(at worktreeURL: URL) async -> [String] {
    let path = worktreeURL.path(percentEncoded: false)
    do {
      let output = try await runGit(
        operation: .untrackedFilePaths,
        arguments: ["-C", path, "-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard"]
      )
      return
        output
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    } catch {
      return []
    }
  }

  nonisolated func showFileAtHEAD(_ relativePath: String, in worktreeURL: URL) async -> String? {
    let path = worktreeURL.path(percentEncoded: false)
    do {
      return try await runGit(
        operation: .showFile,
        arguments: ["-C", path, "show", "HEAD:\(relativePath)"]
      )
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
    let remotes =
      remotesOutput
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

  nonisolated func removeWorktree(_ worktree: Worktree, deleteBranch: Bool) async throws -> URL {
    try await removeWorktree(
      worktree,
      deleteBranch: deleteBranch,
      endpoint: .local,
      hostProfile: nil
    )
  }

  nonisolated func removeWorktree(
    _ worktree: Worktree,
    deleteBranch: Bool,
    endpoint: RepositoryEndpoint,
    hostProfile: SSHHostProfile?
  ) async throws -> URL {
    switch endpoint {
    case .local:
      return try await localRemoveWorktree(worktree, deleteBranch: deleteBranch)
    case .remote(_, let remotePath):
      return try await remoteRemoveWorktree(
        worktree,
        deleteBranch: deleteBranch,
        remotePath: remotePath,
        hostProfile: hostProfile
      )
    }
  }

  nonisolated private func localRemoveWorktree(_ worktree: Worktree, deleteBranch: Bool) async throws -> URL {
    let rootPath = worktree.repositoryRootURL.path(percentEncoded: false)
    let worktreeURL = worktree.workingDirectory.standardizedFileURL
    let worktreePath = worktreeURL.path(percentEncoded: false)
    let relocatedURL = Self.relocateWorktreeDirectory(worktreeURL)
    if let relocatedURL {
      do {
        _ = try await runGit(
          operation: .worktreePrune,
          arguments: ["-C", rootPath, "worktree", "prune", "--expire=now"]
        )
      } catch {
        await runGitWorktreeRemove(rootPath: rootPath, worktreePath: worktreePath)
      }
      if deleteBranch, !worktree.name.isEmpty {
        let names = try await localBranchNames(for: worktree.repositoryRootURL)
        if names.contains(worktree.name.lowercased()) {
          _ = try? await runGit(
            operation: .branchDelete,
            arguments: ["-C", rootPath, "branch", "-D", worktree.name]
          )
        }
      }
      Task.detached {
        try? FileManager.default.removeItem(at: relocatedURL)
      }
      return worktree.workingDirectory
    }
    await runGitWorktreeRemove(rootPath: rootPath, worktreePath: worktreePath)
    if deleteBranch, !worktree.name.isEmpty {
      let names = try await localBranchNames(for: worktree.repositoryRootURL)
      if names.contains(worktree.name.lowercased()) {
        _ = try? await runGit(
          operation: .branchDelete,
          arguments: ["-C", rootPath, "branch", "-D", worktree.name]
        )
      }
    }
    return worktree.workingDirectory
  }

  nonisolated private func parseShortstat(_ output: String) -> (added: Int, removed: Int) {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return (0, 0)
    }
    var added = 0
    var removed = 0
    if let match = trimmed.firstMatch(of: /(\d+)\s+insertions?\(\+\)/) {
      added = Int(match.1) ?? 0
    }
    if let match = trimmed.firstMatch(of: /(\d+)\s+deletions?\(-\)/) {
      removed = Int(match.1) ?? 0
    }
    return (added, removed)
  }

  nonisolated private func parseFileListCount(_ output: String) -> Int {
    output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .count
  }

  nonisolated private func worktrees(
    from entries: [GitWtWorktreeEntry],
    repositoryRootURL: URL,
    detailBaseURL: URL,
    endpoint: RepositoryEndpoint,
    includeCreationDates: Bool
  ) -> [Worktree] {
    let worktreeEntries = entries.enumerated().map { index, entry in
      let worktreeURL = URL(fileURLWithPath: entry.path).standardizedFileURL
      let name = entry.branch.isEmpty ? worktreeURL.lastPathComponent : entry.branch
      let detail = Self.relativePath(from: detailBaseURL, to: worktreeURL)
      let id = worktreeURL.path(percentEncoded: false)
      let createdAt: Date?
      if includeCreationDates {
        let resourceValues = try? worktreeURL.resourceValues(forKeys: [
          .creationDateKey, .contentModificationDateKey,
        ])
        createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate
      } else {
        createdAt = nil
      }
      let sortDate = createdAt ?? .distantPast
      return WorktreeSortEntry(
        worktree: Worktree(
          id: id,
          name: name,
          detail: detail,
          workingDirectory: worktreeURL,
          repositoryRootURL: repositoryRootURL,
          endpoint: endpoint,
          createdAt: createdAt
        ),
        createdAt: sortDate,
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

  nonisolated private func lastNonEmptyLine(in output: String) -> String? {
    output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .last { !$0.isEmpty }
  }

  nonisolated private func parseLocalRefsWithUpstream(_ output: String) -> [String] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard let local = parts.first else {
          return nil
        }
        let localRef = String(local).trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamRef =
          parts.count > 1
          ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
          : ""
        if !upstreamRef.isEmpty {
          return upstreamRef
        }
        return localRef.isEmpty ? nil : localRef
      }
  }

  nonisolated private func parseRemoteWorktreeEntries(_ output: String) -> [GitWtWorktreeEntry] {
    var entries: [GitWtWorktreeEntry] = []
    var currentPath: String?
    var currentBranch = ""
    var currentHead = ""
    var currentIsBare = false

    func commitCurrentEntry() {
      guard let currentPath else { return }
      entries.append(
        GitWtWorktreeEntry(
          branch: currentBranch,
          path: currentPath,
          head: currentHead,
          isBare: currentIsBare
        )
      )
    }

    for line in output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      let value = String(line)
      if value.isEmpty {
        commitCurrentEntry()
        currentPath = nil
        currentBranch = ""
        currentHead = ""
        currentIsBare = false
        continue
      }
      if value.hasPrefix("worktree ") {
        if currentPath != nil {
          commitCurrentEntry()
          currentBranch = ""
          currentHead = ""
          currentIsBare = false
        }
        currentPath = String(value.dropFirst("worktree ".count))
        continue
      }
      if value.hasPrefix("branch ") {
        let ref = String(value.dropFirst("branch ".count))
        currentBranch = ref.replacing("refs/heads/", with: "")
        continue
      }
      if value.hasPrefix("HEAD ") {
        currentHead = String(value.dropFirst("HEAD ".count))
        continue
      }
      if value == "bare" {
        currentIsBare = true
      }
    }

    commitCurrentEntry()
    return entries
  }

  nonisolated private func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  nonisolated private func normalizeRemoteRef(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    let prefix = "refs/remotes/"
    if trimmed.hasPrefix(prefix) {
      return String(trimmed.dropFirst(prefix.count))
    }
    return trimmed
  }

  nonisolated private func localHeadBranchRef(for repoRoot: URL) async throws -> String? {
    let path = repoRoot.path(percentEncoded: false)
    let output = try await runGit(
      operation: .localHeadRef,
      arguments: ["-C", path, "symbolic-ref", "--short", "HEAD"]
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  nonisolated private func resolveLocalHead(_ localHead: String?, repoRoot: URL) async -> String? {
    guard let localHead else { return nil }
    if await refExists(localHead, repoRoot: repoRoot) {
      return localHead
    }
    return nil
  }

  nonisolated static func preferredBaseRef(remote: String?, localHead: String?) -> String? {
    remote ?? localHead
  }

  nonisolated private func refExists(_ ref: String, repoRoot: URL) async -> Bool {
    let path = repoRoot.path(percentEncoded: false)
    do {
      _ = try await runGit(
        operation: .defaultRemoteBranchRef,
        arguments: ["-C", path, "rev-parse", "--verify", "--quiet", ref]
      )
      return true
    } catch {
      return false
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

  nonisolated private func runRemoteGit(
    operation: GitOperation,
    command: String,
    hostProfile: SSHHostProfile?,
    timeoutSeconds: Int
  ) async throws -> RemoteExecutionClient.Output {
    guard let hostProfile else {
      throw GitClientError.commandFailed(command: command, message: "Missing SSH host profile")
    }
    let output: RemoteExecutionClient.Output
    do {
      output = try await remoteExecution.run(hostProfile, command, timeoutSeconds)
    } catch {
      gitLogger.warning("git command failed operation=\(operation.rawValue) exit_code=-1")
      throw GitClientError.commandFailed(command: command, message: error.localizedDescription)
    }
    guard output.exitCode == 0 else {
      throw wrapRemoteExecutionFailure(output, operation: operation, command: command)
    }
    return output
  }

  nonisolated private func buildRemoteGitCommand(
    remotePath: String,
    arguments: [String]
  ) -> String {
    (["git", "-C", SSHCommandSupport.shellEscape(remotePath)] + arguments.map(Self.remoteShellToken))
      .joined(separator: " ")
  }

  nonisolated private func buildRemoteCreateWorktreeCommand(
    remotePath: String,
    worktreePath: String,
    name: String,
    baseRef: String
  ) -> String {
    var arguments = [
      "worktree",
      "add",
      "-b",
      name,
      worktreePath,
    ]
    if !baseRef.isEmpty {
      arguments.append(baseRef)
    }
    let gitCommand = buildRemoteGitCommand(
      remotePath: remotePath,
      arguments: arguments
    )
    return "\(gitCommand) && printf '%s\\n' \(SSHCommandSupport.shellEscape(worktreePath))"
  }

  nonisolated private func runWtList(repoRoot: URL) async throws -> String {
    let wtURL = try wtScriptURL()
    let arguments = ["ls", "--json"]
    return try await runBundledWtProcess(
      operation: .worktreeList,
      executableURL: wtURL,
      arguments: arguments,
      currentDirectoryURL: repoRoot
    )
  }

  nonisolated private func wtScriptURL() throws -> URL {
    guard let url = Bundle.main.url(forResource: "wt", withExtension: nil, subdirectory: "git-wt") else {
      fatalError("Bundled wt script not found")
    }
    return url
  }

  nonisolated private func runBundledWtProcess(
    operation: GitOperation,
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL?
  ) async throws -> String {
    let command = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")
    do {
      return try await shell.run(executableURL, arguments, currentDirectoryURL).stdout
    } catch {
      guard shouldFallbackToLoginShell(error) else {
        throw wrapShellError(error, operation: operation, command: command)
      }
      gitLogger.info("Falling back to login shell for \(operation.rawValue)")
      do {
        return try await shell.runLogin(executableURL, arguments, currentDirectoryURL).stdout
      } catch {
        throw wrapShellError(error, operation: operation, command: command)
      }
    }
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

  nonisolated private static func remoteShellToken(_ value: String) -> String {
    let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:")
    if !value.isEmpty,
      value.rangeOfCharacter(from: safeCharacters.inverted) == nil
    {
      return value
    }
    return SSHCommandSupport.shellEscape(value)
  }

  nonisolated private func runGitWorktreeRemove(
    rootPath: String,
    worktreePath: String
  ) async {
    _ = try? await runGit(
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
  }

  nonisolated private func remoteRemoveWorktree(
    _ worktree: Worktree,
    deleteBranch: Bool,
    remotePath: String,
    hostProfile: SSHHostProfile?
  ) async throws -> URL {
    let worktreePath = worktree.workingDirectory.standardizedFileURL.path(percentEncoded: false)
    let removeCommand = buildRemoteGitCommand(
      remotePath: remotePath,
      arguments: ["worktree", "remove", "--force", worktreePath]
    )
    _ = try await runRemoteGit(
      operation: .worktreeRemove,
      command: removeCommand,
      hostProfile: hostProfile,
      timeoutSeconds: remoteGitTimeoutSeconds
    )
    if deleteBranch, !worktree.name.isEmpty {
      let deleteBranchCommand = buildRemoteGitCommand(
        remotePath: remotePath,
        arguments: ["branch", "-D", worktree.name]
      )
      _ = try? await runRemoteGit(
        operation: .branchDelete,
        command: deleteBranchCommand,
        hostProfile: hostProfile,
        timeoutSeconds: remoteGitTimeoutSeconds
      )
    }
    return worktree.workingDirectory
  }

  nonisolated private static func relocateWorktreeDirectory(_ worktreeURL: URL) -> URL? {
    let fileManager = FileManager.default
    let worktreePath = worktreeURL.path(percentEncoded: false)
    guard fileManager.fileExists(atPath: worktreePath) else {
      return nil
    }
    let candidates = [
      URL(filePath: "/tmp", directoryHint: .isDirectory),
      fileManager.temporaryDirectory,
    ]
    for baseURL in candidates {
      let trashBaseURL = baseURL.appending(
        path: "supacode-worktree-trash",
        directoryHint: URL.DirectoryHint.isDirectory
      )
      do {
        try fileManager.createDirectory(at: trashBaseURL, withIntermediateDirectories: true)
      } catch {
        continue
      }
      let destinationURL = trashBaseURL.appending(
        path: "\(worktreeURL.lastPathComponent)-\(UUID().uuidString)",
        directoryHint: URL.DirectoryHint.isDirectory
      )
      do {
        try fileManager.moveItem(at: worktreeURL, to: destinationURL)
        return destinationURL
      } catch {
        continue
      }
    }
    return nil
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

private nonisolated let gitLogger = SupaLogger("Git")
private nonisolated let remoteGitTimeoutSeconds = 30
private nonisolated let remoteGitCreateTimeoutSeconds = 120

nonisolated private func makeDefaultRemoteExecutionClient(shell: ShellClient) -> RemoteExecutionClient {
  RemoteExecutionClient(
    run: { profile, command, timeoutSeconds in
      let endpointKey = [profile.host, profile.user, profile.port.map(String.init) ?? "22"]
        .joined(separator: "|")
      let controlPath = SSHCommandSupport.controlSocketPath(endpointKey: endpointKey)

      var options = SSHCommandSupport.connectivityOptions(includeBatchMode: profile.authMethod != .password)
      options += ["-o", "ControlPath=\(controlPath)"]

      if let port = profile.port {
        options += ["-p", "\(port)"]
      }

      let target = profile.user.isEmpty ? profile.host : "\(profile.user)@\(profile.host)"
      let arguments = options + [target, command]
      do {
        let output = try await shell.runWithTimeout(
          URL(fileURLWithPath: "/usr/bin/ssh"),
          arguments,
          nil,
          timeoutSeconds: timeoutSeconds
        )
        return RemoteExecutionClient.Output(stdout: output.stdout, stderr: output.stderr, exitCode: output.exitCode)
      } catch let shellError as ShellClientError {
        return RemoteExecutionClient.Output(
          stdout: shellError.stdout,
          stderr: shellError.stderr,
          exitCode: shellError.exitCode
        )
      }
    }
  )
}

nonisolated private func shouldFallbackToLoginShell(_ error: Error) -> Bool {
  guard let shellError = error as? ShellClientError else {
    return false
  }
  if shellError.exitCode == 127 {
    return true
  }
  let output = "\(shellError.stderr)\n\(shellError.stdout)".lowercased()
  return output.contains("command not found")
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
  gitLogger.warning("git command failed operation=\(operation.rawValue) exit_code=\(exitCode)")
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

nonisolated private func wrapRemoteExecutionFailure(
  _ output: RemoteExecutionClient.Output,
  operation: GitOperation,
  command: String
) -> GitClientError {
  var messageParts: [String] = []
  if !output.stdout.isEmpty {
    messageParts.append("stdout:\n\(output.stdout)")
  }
  if !output.stderr.isEmpty {
    messageParts.append("stderr:\n\(output.stderr)")
  }
  let gitError = GitClientError.commandFailed(
    command: command,
    message: messageParts.joined(separator: "\n")
  )
  gitLogger.warning("git command failed operation=\(operation.rawValue) exit_code=\(output.exitCode)")
  #if !DEBUG
    SentrySDK.logger.error(
      "git command failed",
      attributes: [
        "operation": operation.rawValue,
        "exit_code": Int(output.exitCode),
      ]
    )
  #endif
  return gitError
}

struct GitWtWorktreeEntry: Decodable, Equatable {
  let branch: String
  let path: String
  let head: String
  let isBare: Bool

  enum CodingKeys: String, CodingKey {
    case branch
    case path
    case head
    case isBare = "is_bare"
  }

}
