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
        let output = try await runGit(arguments: ["-C", repoRoot.path(percentEncoded: false), "worktree", "list", "--porcelain"])
        return try GitWorktreeParser.parse(output, repoRoot: repoRoot)
    }

    nonisolated private func runGit(arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
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
                let command = (["git"] + arguments).joined(separator: " ")
                let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitClientError.commandFailed(command: command, message: message)
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

struct GitWorktreeParser {
    nonisolated static func parse(_ output: String, repoRoot: URL) throws -> [Worktree] {
        let lines = output.components(separatedBy: .newlines)
        var worktrees: [Worktree] = []
        var currentPath: String?
        var currentBranch: String?
        var isDetached = false

        func flush() {
            guard let path = currentPath else { return }
            let worktreeURL = URL(fileURLWithPath: path).standardizedFileURL
            let branchName: String
            if isDetached {
                branchName = "detached"
            } else if let currentBranch {
                if currentBranch.hasPrefix("refs/heads/") {
                    branchName = currentBranch.replacing("refs/heads/", with: "")
                } else {
                    branchName = currentBranch
                }
            } else {
                branchName = "unknown"
            }
            let detail = relativePath(from: repoRoot, to: worktreeURL)
            let id = worktreeURL.path(percentEncoded: false)
            worktrees.append(Worktree(id: id, name: branchName, detail: detail, workingDirectory: worktreeURL))
        }

        for line in lines {
            if line.isEmpty {
                flush()
                currentPath = nil
                currentBranch = nil
                isDetached = false
                continue
            }
            if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst("worktree ".count))
                continue
            }
            if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst("branch ".count))
                isDetached = false
                continue
            }
            if line == "detached" {
                isDetached = true
            }
        }

        flush()
        return worktrees
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
}
