import Testing

@testable import supacode

struct WorktreeInfoParsingTests {
  @Test func parseAheadBehindCountsHandlesTabs() {
    let result = parseAheadBehindCounts("2\t5")
    #expect(result?.behind == 2)
    #expect(result?.ahead == 5)
  }

  @Test func parseGitStatusV2TracksBranchAndCounts() {
    let output = """
    # branch.oid 1234567890abcdef
    # branch.head main
    # branch.upstream origin/main
    # branch.ab +2 -1
    1 M. N... 100644 100644 100644 abcdef1 abcdef2 file.swift
    1 .M N... 100644 100644 100644 abcdef1 abcdef2 other.swift
    ? new.swift
    """
    let result = parseGitStatusV2(output)
    #expect(result.branchHead == "main")
    #expect(result.upstream == "origin/main")
    #expect(result.ahead == 2)
    #expect(result.behind == 1)
    #expect(result.staged == 1)
    #expect(result.unstaged == 1)
    #expect(result.untracked == 1)
  }

  @Test func parseMergeTreeConflictDetectsMarkers() {
    let output = "<<<<<<< HEAD\nconflict\n>>>>>>> branch"
    #expect(parseMergeTreeConflict(output))
  }

  @Test func parseDefaultBranchFromSymbolicRefHandlesOrigin() {
    let output = "refs/remotes/origin/main"
    #expect(parseDefaultBranchFromSymbolicRef(output) == "main")
  }
}
