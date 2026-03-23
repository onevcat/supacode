import Foundation
import Testing

@testable import supacode

struct GitLogCommitTests {
  @Test
  func parsesSingleCommit() {
    let fs = GitLogCommit.fieldSeparator
    let rs = GitLogCommit.recordSeparator
    let output =
      "abc1234567890\(fs)abc1234\(fs)Alice\(fs)2026-03-20T10:00:00+00:00\(fs)feat: add feature\(fs)feat: add feature\n\nSome body text\(rs)"

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
    let fs = GitLogCommit.fieldSeparator
    let rs = GitLogCommit.recordSeparator
    let output = [
      "hash1\(fs)h1\(fs)Alice\(fs)2026-03-20T10:00:00+00:00\(fs)first\(fs)first\(rs)",
      "hash2\(fs)h2\(fs)Bob\(fs)2026-03-19T09:00:00+00:00\(fs)second\(fs)second\(rs)",
    ].joined()

    let commits = GitLogCommit.parse(output)

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
    let fs = GitLogCommit.fieldSeparator
    let rs = GitLogCommit.recordSeparator
    let body = "subject line\n\nLine 1\nLine 2\nLine 3"
    let output = "hash1\(fs)h1\(fs)Alice\(fs)2026-03-20T10:00:00+00:00\(fs)subject line\(fs)\(body)\(rs)"

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].body.contains("Line 2"))
  }

  @Test
  func skipsIncompleteRecords() {
    let fs = GitLogCommit.fieldSeparator
    let rs = GitLogCommit.recordSeparator
    let output = "onlyOneField\(rs)hash1\(fs)h1\(fs)Alice\(fs)2026-03-20T10:00:00+00:00\(fs)ok\(fs)ok\(rs)"

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].subject == "ok")
  }

  @Test
  func parsesDateCorrectly() {
    let fs = GitLogCommit.fieldSeparator
    let rs = GitLogCommit.recordSeparator
    let output = "hash1\(fs)h1\(fs)Alice\(fs)2026-03-20T10:30:00+00:00\(fs)test\(fs)test\(rs)"

    let commits = GitLogCommit.parse(output)

    #expect(commits.count == 1)
    #expect(commits[0].authorDate != .distantPast)
  }
}
