import Foundation
import Testing

@testable import supacode

struct GitLogCommitTests {
  private let fieldSep = GitLogCommit.fieldSeparator
  private let recordSep = GitLogCommit.recordSeparator

  @Test
  func parsesSingleCommit() {
    let output =
      [
        "abc1234567890", "abc1234", "Alice", "2026-03-20T10:00:00+00:00",
        "feat: add feature", "feat: add feature\n\nSome body text",
      ].joined(separator: fieldSep) + recordSep

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].hash == "abc1234567890")
    #expect(commits[0].shortHash == "abc1234")
    #expect(commits[0].authorName == "Alice")
    #expect(commits[0].subject == "feat: add feature")
    #expect(commits[0].body.contains("Some body text"))
  }

  @Test
  func parsesMultipleCommits() {
    let first =
      ["hash1", "h1", "Alice", "2026-03-20T10:00:00+00:00", "first", "first"]
      .joined(separator: fieldSep) + recordSep
    let second =
      ["hash2", "h2", "Bob", "2026-03-19T09:00:00+00:00", "second", "second"]
      .joined(separator: fieldSep) + recordSep

    let commits = GitLogCommit.parse(first + second)

    #expect(commits.count == 2)
    #expect(commits[0].shortHash == "h1")
    #expect(commits[1].authorName == "Bob")
  }

  @Test
  func parsesEmptyOutput() {
    let commits = GitLogCommit.parse("")
    #expect(commits.isEmpty)
  }

  @Test
  func parsesWhitespaceOnlyOutput() {
    let commits = GitLogCommit.parse("  \n\n  ")
    #expect(commits.isEmpty)
  }

  @Test
  func parsesCommitWithNewlinesInBody() {
    let body = "subject line\n\nLine 1\nLine 2\nLine 3"
    let output =
      ["hash1", "h1", "Alice", "2026-03-20T10:00:00+00:00", "subject line", body]
      .joined(separator: fieldSep) + recordSep

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].body.contains("Line 2"))
  }

  @Test
  func skipsIncompleteRecords() {
    let incomplete = "onlyOneField" + recordSep
    let valid =
      ["hash1", "h1", "Alice", "2026-03-20T10:00:00+00:00", "ok", "ok"]
      .joined(separator: fieldSep) + recordSep

    let commits = GitLogCommit.parse(incomplete + valid)

    #expect(commits.count == 1)
    #expect(commits[0].subject == "ok")
  }

  @Test
  func parsesDateCorrectly() {
    let output =
      ["hash1", "h1", "Alice", "2026-03-20T10:30:00+00:00", "test", "test"]
      .joined(separator: fieldSep) + recordSep

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].authorDate != .distantPast)
  }
}
