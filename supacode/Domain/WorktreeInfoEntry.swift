import Foundation

struct WorktreeInfoEntry: Equatable, Hashable {
  var addedLines: Int?
  var removedLines: Int?
  var pullRequestNumber: Int?

  var isEmpty: Bool {
    addedLines == nil && removedLines == nil && pullRequestNumber == nil
  }
}
