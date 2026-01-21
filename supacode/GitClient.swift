import Foundation

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
    nonisolated init() {}

    nonisolated func repoRoot(for path: URL) async throws -> URL {
        let raw = try await runGit(arguments: ["-C", path.path(percentEncoded: false), "rev-parse", "--show-toplevel"])
        if raw.isEmpty {
            let command = "git -C \(path.path(percentEncoded: false)) rev-parse --show-toplevel"
            throw GitClientError.commandFailed(command: command, message: "Empty output")
        }
        return URL(fileURLWithPath: raw).standardizedFileURL
    }

    nonisolated func worktrees(for repoRoot: URL) async throws -> [Worktree] {
        let baseDirectory = wtBaseDirectory(for: repoRoot)
        let output = try await runWtList(repoRoot: repoRoot, baseDirectory: baseDirectory)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        let data = Data(trimmed.utf8)
        let entries = try JSONDecoder().decode([GitWtWorktreeEntry].self, from: data)
        let worktrees = entries.enumerated().map { index, entry -> (worktree: Worktree, createdAt: Date, index: Int) in
            let worktreeURL = URL(fileURLWithPath: entry.path).standardizedFileURL
            let detail = Self.relativePath(from: baseDirectory, to: worktreeURL)
            let id = worktreeURL.path(percentEncoded: false)
            let resourceValues = try? worktreeURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? .distantPast
            return (
                worktree: Worktree(id: id, name: entry.branch, detail: detail, workingDirectory: worktreeURL),
                createdAt: createdAt,
                index: index
            )
        }
        return worktrees
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
        let output = try await runGit(arguments: [
            "-C",
            path,
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/heads"
        ])
        let names = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Set(names)
    }

    nonisolated func createWorktree(named name: String, in repoRoot: URL) async throws -> Worktree {
        let baseDirectory = wtBaseDirectory(for: repoRoot)
        let wtURL = try wtScriptURL()
        let output = try await runProcess(
            executableURL: wtURL,
            arguments: ["sw", name, "--base", baseDirectory.path(percentEncoded: false)],
            currentDirectoryURL: repoRoot
        )
        let pathLine = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        if pathLine.isEmpty {
            let command = "\(wtURL.lastPathComponent) sw \(name) --base \(baseDirectory.path(percentEncoded: false))"
            throw GitClientError.commandFailed(command: command, message: "Empty output")
        }
        let worktreeURL = URL(fileURLWithPath: pathLine).standardizedFileURL
        let detail = Self.relativePath(from: baseDirectory, to: worktreeURL)
        let id = worktreeURL.path(percentEncoded: false)
        return Worktree(id: id, name: name, detail: detail, workingDirectory: worktreeURL)
    }

    nonisolated func isWorktreeDirty(at worktreeURL: URL) async throws -> Bool {
        let path = worktreeURL.path(percentEncoded: false)
        let output = try await runGit(arguments: ["-C", path, "status", "--porcelain"])
        return WorktreeDirtCheck.isDirty(statusOutput: output)
    }

    nonisolated func removeWorktree(named name: String, in repoRoot: URL, force: Bool) async throws -> URL {
        let baseDirectory = wtBaseDirectory(for: repoRoot)
        let wtURL = try wtScriptURL()
        var arguments = ["rm", "--base", baseDirectory.path(percentEncoded: false)]
        if force {
            arguments.append("--force")
        }
        arguments.append(name)
        let output = try await runProcess(
            executableURL: wtURL,
            arguments: arguments,
            currentDirectoryURL: repoRoot
        )
        let pathLine = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        if pathLine.isEmpty {
            let command = ([wtURL.lastPathComponent] + arguments).joined(separator: " ")
            throw GitClientError.commandFailed(command: command, message: "Empty output")
        }
        return URL(fileURLWithPath: pathLine).standardizedFileURL
    }

    nonisolated func githubOwner(for repoRoot: URL) async -> String? {
        guard let remote = await originRemoteURL(for: repoRoot) else { return nil }
        return Self.githubOwner(fromRemote: remote)
    }

    nonisolated private func runGit(arguments: [String]) async throws -> String {
        let env = URL(fileURLWithPath: "/usr/bin/env")
        return try await runProcess(
            executableURL: env,
            arguments: ["git"] + arguments,
            currentDirectoryURL: nil
        )
    }

    nonisolated private func runWtList(repoRoot: URL, baseDirectory: URL) async throws -> String {
        let wtURL = try wtScriptURL()
        let arguments = ["ls", "--json", "--base", baseDirectory.path(percentEncoded: false)]
        print(
            "\(wtURL.lastPathComponent) \(arguments.joined(separator: " "))"
        )
        let output = try await runProcess(
            executableURL: wtURL,
            arguments: arguments,
            currentDirectoryURL: repoRoot
        )
        print(output)
        print()
        return output
    }

    nonisolated private func wtScriptURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "wt", withExtension: nil, subdirectory: "git-wt") {
            return url
        }
        throw GitClientError.commandFailed(command: "wt ls --json", message: "Bundled wt script not found")
    }

    nonisolated private func originRemoteURL(for repoRoot: URL) async -> String? {
        let path = repoRoot.path(percentEncoded: false)
        let raw = try? await runGit(arguments: ["-C", path, "config", "--get", "remote.origin.url"])
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private func wtBaseDirectory(for repoRoot: URL) -> URL {
        let repoName = repoRoot.lastPathComponent
        let fallback = repoRoot.path(percentEncoded: false).replacingOccurrences(of: "/", with: "_")
        let name = repoName.isEmpty ? fallback : repoName
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".supacode/repos", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    nonisolated private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            let errorOutput = String(decoding: errorData, as: UTF8.self)
            if process.terminationStatus != 0 {
                let command = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")
                let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitClientError.commandFailed(command: command, message: message)
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    nonisolated private static func relativePath(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var index = 0
        while index < min(baseComponents.count, targetComponents.count), baseComponents[index] == targetComponents[index] {
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

    nonisolated private static func githubOwner(fromRemote remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hostRange = trimmed.range(of: "github.com") else { return nil }
        let afterHost = trimmed[hostRange.upperBound...]
        let path: Substring
        if afterHost.hasPrefix(":") {
            path = afterHost.dropFirst()
        } else if afterHost.hasPrefix("/") {
            path = afterHost.dropFirst()
        } else {
            return nil
        }
        let components = path.split(separator: "/")
        guard let owner = components.first, !owner.isEmpty else { return nil }
        return String(owner)
    }
}

struct GitWtWorktreeEntry: Decodable {
    let branch: String
    let path: String
    let head: String
}
