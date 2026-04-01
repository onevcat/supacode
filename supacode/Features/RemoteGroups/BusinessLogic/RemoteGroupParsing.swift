import Foundation

nonisolated enum RemoteGroupParsing {
  static let scope = "multi-tmux"
  private static let prefix = "\(scope):"

  static func parseGroup(from reuseKey: String) -> String? {
    let text = reuseKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix(prefix) else {
      return nil
    }
    let suffix = String(text.dropFirst(prefix.count))
    let firstSegment = String(
      suffix.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    )
    let slug = slugify(firstSegment)
    return slug.isEmpty ? nil : slug
  }

  static func slugify(_ text: String) -> String {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let replaced = String(
      normalized.map { character in
        if character.isLetter || character.isNumber {
          character
        } else {
          "-"
        }
      }
    )
    return
      replaced
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }
}
