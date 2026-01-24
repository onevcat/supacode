import Foundation

nonisolated func parseAheadBehindCounts(_ output: String) -> (behind: Int, ahead: Int)? {
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty {
    return nil
  }
  let parts = trimmed.split { $0 == " " || $0 == "\t" }
  guard parts.count >= 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
    return nil
  }
  return (behind, ahead)
}

nonisolated func parseGitStatusV2(_ output: String) -> GitStatusV2Summary {
  var summary = GitStatusV2Summary()
  for line in output.split(whereSeparator: \.isNewline) {
    if line.hasPrefix("# ") {
      let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard parts.count >= 3 else { continue }
      let key = parts[1]
      let value = String(parts[2])
      switch key {
      case "branch.head":
        summary.branchHead = value
      case "branch.oid":
        summary.branchOid = value
      case "branch.upstream":
        summary.upstream = value
      case "branch.ab":
        let tokens = value.split(separator: " ")
        for token in tokens {
          if token.hasPrefix("+") {
            summary.ahead = Int(token.dropFirst())
          } else if token.hasPrefix("-") {
            summary.behind = Int(token.dropFirst())
          }
        }
      default:
        break
      }
      continue
    }
    if line.hasPrefix("? ") {
      summary.untracked += 1
      continue
    }
    if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
      let parts = line.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count > 1 else { continue }
      let status = parts[1]
      if status.count >= 2 {
        let chars = Array(status)
        if chars[0] != "." {
          summary.staged += 1
        }
        if chars[1] != "." {
          summary.unstaged += 1
        }
      }
    }
  }
  return summary
}

nonisolated func parseDefaultBranchFromSymbolicRef(_ output: String) -> String? {
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty {
    return nil
  }
  let parts = trimmed.split(separator: "/")
  return parts.last.map(String.init)
}

nonisolated func parseMergeTreeConflict(_ output: String) -> Bool {
  output.contains("<<<<<<<") || output.contains(">>>>>>>") || output.contains("|||||||")
}

nonisolated struct GitStatusV2Summary: Equatable {
  var branchHead: String?
  var branchOid: String?
  var upstream: String?
  var ahead: Int?
  var behind: Int?
  var staged = 0
  var unstaged = 0
  var untracked = 0

  var shortOid: String? {
    guard let branchOid, !branchOid.isEmpty else { return nil }
    return String(branchOid.prefix(7))
  }
}
