import Foundation

nonisolated struct GitLogCommit: Identifiable, Hashable, Sendable {
  let hash: String
  let shortHash: String
  let authorName: String
  let authorDate: Date
  let subject: String
  let body: String

  var id: String { hash }

  static let fieldSeparator = "\u{1F}"
  static let recordSeparator = "\u{1E}"

  static let logFormat: String = [
    "%H", "%h", "%an", "%aI", "%s", "%B",
  ].joined(separator: fieldSeparator) + recordSeparator

  static func parse(_ output: String) -> [GitLogCommit] {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return trimmed.split(separator: Character(recordSeparator)).compactMap { record in
      let fields = record.split(
        separator: Character(fieldSeparator),
        maxSplits: 5,
        omittingEmptySubsequences: false
      )
      guard fields.count >= 6 else { return nil }
      let hash = String(fields[0])
      let shortHash = String(fields[1])
      let authorName = String(fields[2])
      let dateString = String(fields[3])
      let subject = String(fields[4])
      let body = String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines)
      let date = ISO8601DateFormatter().date(from: dateString) ?? .distantPast
      return GitLogCommit(
        hash: hash,
        shortHash: shortHash,
        authorName: authorName,
        authorDate: date,
        subject: subject,
        body: body,
      )
    }
  }
}
