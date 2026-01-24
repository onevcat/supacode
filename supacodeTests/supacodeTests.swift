//
//  supacodeTests.swift
//  supacodeTests
//
//  Created by khoi on 20/1/26.
//

import Testing

@testable import supacode

struct SupacodeTests {

  @Test func example() throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
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
}
