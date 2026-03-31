import ComposableArchitecture
import Foundation

struct TerminalLayoutPersistenceClient {
  var clearSnapshot: @Sendable () async -> Bool
}

extension TerminalLayoutPersistenceClient: DependencyKey {
  static let liveValue = TerminalLayoutPersistenceClient(
    clearSnapshot: {
      do {
        try SupacodePaths.migrateLegacyCacheFilesIfNeeded()
        let url = SupacodePaths.terminalLayoutSnapshotURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
          return true
        }
        try FileManager.default.removeItem(at: url)
        return true
      } catch {
        return false
      }
    }
  )

  static let testValue = TerminalLayoutPersistenceClient(
    clearSnapshot: { true }
  )
}

extension DependencyValues {
  var terminalLayoutPersistence: TerminalLayoutPersistenceClient {
    get { self[TerminalLayoutPersistenceClient.self] }
    set { self[TerminalLayoutPersistenceClient.self] = newValue }
  }
}

nonisolated struct TerminalLayoutSnapshotPayload: Codable, Equatable, Sendable {
  nonisolated static let currentVersion = 1
  nonisolated static let maxSnapshotFileBytes = 2 * 1024 * 1024
  nonisolated static let maxWorktrees = 128
  nonisolated static let maxTabsPerWorktree = 128
  nonisolated static let maxSplitNodesPerTab = 1024
  nonisolated static let maxSplitDepth = 24

  let version: Int
  let worktrees: [SnapshotWorktree]

  init(worktrees: [SnapshotWorktree]) {
    version = Self.currentVersion
    self.worktrees = worktrees
  }

  init(version: Int, worktrees: [SnapshotWorktree]) {
    self.version = version
    self.worktrees = worktrees
  }

  static func decodeValidated(from data: Data) -> TerminalLayoutSnapshotPayload? {
    guard !data.isEmpty, data.count <= Self.maxSnapshotFileBytes else {
      return nil
    }
    let decoder = JSONDecoder()
    guard let payload = try? decoder.decode(Self.self, from: data) else {
      return nil
    }
    return payload.isValid ? payload : nil
  }

  var isValid: Bool {
    guard version == Self.currentVersion else {
      return false
    }
    guard !worktrees.isEmpty, worktrees.count <= Self.maxWorktrees else {
      return false
    }
    return worktrees.allSatisfy {
      $0.isValid(
        maxTabsPerWorktree: Self.maxTabsPerWorktree,
        maxSplitNodesPerTab: Self.maxSplitNodesPerTab,
        maxSplitDepth: Self.maxSplitDepth
      )
    }
  }
}

extension TerminalLayoutSnapshotPayload {
  nonisolated struct SnapshotWorktree: Codable, Equatable, Sendable {
    let worktreeID: String
    let selectedTabID: String?
    let tabs: [SnapshotTab]

    func isValid(
      maxTabsPerWorktree: Int,
      maxSplitNodesPerTab: Int,
      maxSplitDepth: Int
    ) -> Bool {
      guard hasContent(worktreeID) else {
        return false
      }
      guard !tabs.isEmpty, tabs.count <= maxTabsPerWorktree else {
        return false
      }

      var tabIDs: Set<String> = []
      for tab in tabs {
        guard tabIDs.insert(tab.tabID).inserted else {
          return false
        }
        guard tab.isValid(maxSplitNodesPerTab: maxSplitNodesPerTab, maxSplitDepth: maxSplitDepth) else {
          return false
        }
      }

      if let selectedTabID {
        return tabIDs.contains(selectedTabID)
      }
      return true
    }
  }

  nonisolated struct SnapshotTab: Codable, Equatable, Sendable {
    let tabID: String
    let splitRoot: SnapshotSplitNode

    func isValid(maxSplitNodesPerTab: Int, maxSplitDepth: Int) -> Bool {
      guard hasContent(tabID) else {
        return false
      }
      var nodeCount = 0
      return splitRoot.isValid(
        depth: 1,
        maxDepth: maxSplitDepth,
        nodeCount: &nodeCount,
        maxNodes: maxSplitNodesPerTab
      )
    }
  }

  nonisolated struct SnapshotSplitNode: Codable, Equatable, Sendable {
    let kind: TerminalLayoutSnapshotNodeKind
    let surfaceID: String?
    let direction: TerminalLayoutSnapshotSplitDirection?
    let ratio: Double?
    let children: [SnapshotSplitNode]?

    static func leaf(surfaceID: String) -> SnapshotSplitNode {
      SnapshotSplitNode(
        kind: .leaf,
        surfaceID: surfaceID,
        direction: nil,
        ratio: nil,
        children: nil
      )
    }

    static func split(
      direction: TerminalLayoutSnapshotSplitDirection,
      ratio: Double,
      children: [SnapshotSplitNode]
    ) -> SnapshotSplitNode {
      SnapshotSplitNode(
        kind: .split,
        surfaceID: nil,
        direction: direction,
        ratio: ratio,
        children: children
      )
    }

    func isValid(
      depth: Int,
      maxDepth: Int,
      nodeCount: inout Int,
      maxNodes: Int
    ) -> Bool {
      nodeCount += 1
      guard nodeCount <= maxNodes else {
        return false
      }

      switch kind {
      case .leaf:
        guard hasContent(surfaceID) else {
          return false
        }
        guard direction == nil, ratio == nil else {
          return false
        }
        return children == nil || children?.isEmpty == true

      case .split:
        guard depth < maxDepth else {
          return false
        }
        guard surfaceID == nil else {
          return false
        }
        guard direction != nil else {
          return false
        }
        guard let ratio, ratio > 0, ratio < 1 else {
          return false
        }
        guard let children, children.count == 2 else {
          return false
        }
        return children.allSatisfy {
          $0.isValid(
            depth: depth + 1,
            maxDepth: maxDepth,
            nodeCount: &nodeCount,
            maxNodes: maxNodes
          )
        }
      }
    }
  }
}

nonisolated enum TerminalLayoutSnapshotNodeKind: String, Codable, Sendable {
  case leaf
  case split
}

nonisolated enum TerminalLayoutSnapshotSplitDirection: String, Codable, Sendable {
  case horizontal
  case vertical
}

private nonisolated func hasContent(_ value: String?) -> Bool {
  guard let value else {
    return false
  }
  return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
