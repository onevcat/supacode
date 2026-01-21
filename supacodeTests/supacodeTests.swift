//
//  supacodeTests.swift
//  supacodeTests
//
//  Created by khoi on 20/1/26.
//

import Foundation
import Testing
@testable import supacode

struct supacodeTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func profilePictureURLIncludesSize() {
        let url = Github.profilePictureURL(username: "octocat", size: 64)
        #expect(url?.absoluteString == "https://github.com/octocat.png?size=64")
    }

    @Test func githubOwnerFromHTTPSRemote() async throws {
        let repoRoot = try makeTempRepo(remote: "https://github.com/supabitapp/supacode.git")
        defer { try? removeTempRepo(repoRoot) }
        let owner = await GitClient().githubOwner(for: repoRoot)
        #expect(owner == "supabitapp")
    }

    @Test func githubOwnerFromSSHRemote() async throws {
        let repoRoot = try makeTempRepo(remote: "git@github.com:supabitapp/supacode.git")
        defer { try? removeTempRepo(repoRoot) }
        let owner = await GitClient().githubOwner(for: repoRoot)
        #expect(owner == "supabitapp")
    }

    @Test func worktreeNameGeneratorReturnsRemainingName() {
        let animals = WorktreeNameGenerator.animals
        let expected = animals.last
        let excluded = Set(animals.dropLast())
        let name = WorktreeNameGenerator.nextName(excluding: excluded)
        #expect(name == expected)
    }

    @Test func worktreeNameGeneratorReturnsNilWhenExhausted() {
        let excluded = Set(WorktreeNameGenerator.animals)
        let name = WorktreeNameGenerator.nextName(excluding: excluded)
        #expect(name == nil)
    }

    @Test func worktreeDirtCheckEmptyIsClean() {
        #expect(WorktreeDirtCheck.isDirty(statusOutput: "") == false)
    }

    @Test func worktreeDirtCheckWhitespaceIsClean() {
        #expect(WorktreeDirtCheck.isDirty(statusOutput: " \n") == false)
    }

    @Test func worktreeDirtCheckModifiedIsDirty() {
        let output = " M README.md\n"
        #expect(WorktreeDirtCheck.isDirty(statusOutput: output))
    }

    @Test func worktreeDirtCheckUntrackedIsDirty() {
        let output = "?? new-file.txt\n"
        #expect(WorktreeDirtCheck.isDirty(statusOutput: output))
    }

    private func makeTempRepo(remote: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["remote", "add", "origin", remote], in: root)
        return root
    }

    private func removeTempRepo(_ root: URL) throws {
        try FileManager.default.removeItem(at: root)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
            throw GitClientError.commandFailed(
                command: (["git"] + arguments).joined(separator: " "),
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
