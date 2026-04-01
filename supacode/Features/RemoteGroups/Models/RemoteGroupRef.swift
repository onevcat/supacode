import Foundation

nonisolated struct RemoteGroupRef: Equatable, Identifiable, Sendable {
  var id: String {
    group
  }

  var group: String
  var sessionCount: Int

  static func aggregate(sessions: [RemoteTerminalSession]) -> [RemoteGroupRef] {
    var counts: [String: Int] = [:]

    for session in sessions {
      guard let group = RemoteGroupParsing.parseGroup(from: session.reuseKey) else {
        continue
      }
      counts[group, default: 0] += 1
    }

    return counts.keys.sorted().map { key in
      RemoteGroupRef(group: key, sessionCount: counts[key] ?? 0)
    }
  }
}
