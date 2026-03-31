import Foundation
import Testing

@testable import supacode

struct TerminalLayoutSnapshotPayloadTests {
  @Test func decodeValidatedRoundTripsValidPayload() throws {
    let payload = makePayload()
    let data = try JSONEncoder().encode(payload)

    let decoded = TerminalLayoutSnapshotPayload.decodeValidated(from: data)
    #expect(decoded == payload)
  }

  @Test func decodeValidatedRejectsOversizedData() {
    let data = Data(
      repeating: 0,
      count: TerminalLayoutSnapshotPayload.maxSnapshotFileBytes + 1
    )

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsSchemaVersionMismatch() throws {
    let payload = makePayload(version: TerminalLayoutSnapshotPayload.currentVersion + 1)
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsTooManyWorktrees() throws {
    let worktrees = (0...TerminalLayoutSnapshotPayload.maxWorktrees).map { index in
      makeWorktree(worktreeID: "wt-\(index)")
    }
    let payload = TerminalLayoutSnapshotPayload(worktrees: worktrees)
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsTooManyTabsInWorktree() throws {
    let tabs = (0...TerminalLayoutSnapshotPayload.maxTabsPerWorktree).map { index in
      makeTab(tabID: "tab-\(index)")
    }
    let payload = TerminalLayoutSnapshotPayload(
      worktrees: [
        TerminalLayoutSnapshotPayload.SnapshotWorktree(
          worktreeID: "wt-1",
          selectedTabID: "tab-0",
          tabs: tabs
        ),
      ]
    )
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsTooManySplitNodesInTab() throws {
    var leafIndex = 0
    let root = makeBalancedSplitTree(depth: 10, leafIndex: &leafIndex)
    let payload = makePayload(
      tabID: "tab-large",
      splitRoot: root
    )
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsSplitTreeDepthOverflow() throws {
    var leafIndex = 0
    let root = makeDeepSplitTree(
      splitCount: TerminalLayoutSnapshotPayload.maxSplitDepth,
      leafIndex: &leafIndex
    )
    let payload = makePayload(
      tabID: "tab-deep",
      splitRoot: root
    )
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsIllegalSplitNodeStructure() throws {
    let invalidRoot = TerminalLayoutSnapshotPayload.SnapshotSplitNode(
      kind: .split,
      surfaceID: nil,
      direction: .horizontal,
      ratio: 0.5,
      children: [
        .leaf(surfaceID: "leaf-1")
      ]
    )
    let payload = makePayload(
      tabID: "tab-invalid",
      splitRoot: invalidRoot
    )
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsSelectedTabMissingFromTabs() throws {
    let payload = TerminalLayoutSnapshotPayload(
      worktrees: [
        TerminalLayoutSnapshotPayload.SnapshotWorktree(
          worktreeID: "wt-1",
          selectedTabID: "tab-missing",
          tabs: [
            makeTab(tabID: "tab-1"),
          ]
        ),
      ]
    )
    let data = try JSONEncoder().encode(payload)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }

  @Test func decodeValidatedRejectsTypeMismatchInFields() {
    let invalidJSON = #"""
    {
      "version": 1,
      "worktrees": [
        {
          "worktreeID": "wt-1",
          "selectedTabID": "tab-1",
          "tabs": [
            {
              "tabID": "tab-1",
              "splitRoot": {
                "kind": "split",
                "direction": "horizontal",
                "ratio": "bad",
                "children": []
              }
            }
          ]
        }
      ]
    }
    """#
    let data = Data(invalidJSON.utf8)

    #expect(TerminalLayoutSnapshotPayload.decodeValidated(from: data) == nil)
  }
}

private func makePayload(
  version: Int = TerminalLayoutSnapshotPayload.currentVersion,
  worktreeID: String = "wt-1",
  tabID: String = "tab-1",
  splitRoot: TerminalLayoutSnapshotPayload.SnapshotSplitNode = .leaf(surfaceID: "surface-1")
) -> TerminalLayoutSnapshotPayload {
  TerminalLayoutSnapshotPayload(
    version: version,
    worktrees: [
      TerminalLayoutSnapshotPayload.SnapshotWorktree(
        worktreeID: worktreeID,
        selectedTabID: tabID,
        tabs: [
          makeTab(tabID: tabID, splitRoot: splitRoot),
        ]
      ),
    ]
  )
}

private func makeWorktree(
  worktreeID: String
) -> TerminalLayoutSnapshotPayload.SnapshotWorktree {
  TerminalLayoutSnapshotPayload.SnapshotWorktree(
    worktreeID: worktreeID,
    selectedTabID: "tab-1",
    tabs: [
      makeTab(tabID: "tab-1"),
    ]
  )
}

private func makeTab(
  tabID: String,
  splitRoot: TerminalLayoutSnapshotPayload.SnapshotSplitNode = .leaf(surfaceID: "surface-1")
) -> TerminalLayoutSnapshotPayload.SnapshotTab {
  TerminalLayoutSnapshotPayload.SnapshotTab(
    tabID: tabID,
    splitRoot: splitRoot
  )
}

private func makeBalancedSplitTree(
  depth: Int,
  leafIndex: inout Int
) -> TerminalLayoutSnapshotPayload.SnapshotSplitNode {
  guard depth > 0 else {
    let surfaceID = "surface-\(leafIndex)"
    leafIndex += 1
    return .leaf(surfaceID: surfaceID)
  }
  let left = makeBalancedSplitTree(depth: depth - 1, leafIndex: &leafIndex)
  let right = makeBalancedSplitTree(depth: depth - 1, leafIndex: &leafIndex)
  return .split(direction: .horizontal, ratio: 0.5, children: [left, right])
}

private func makeDeepSplitTree(
  splitCount: Int,
  leafIndex: inout Int
) -> TerminalLayoutSnapshotPayload.SnapshotSplitNode {
  guard splitCount > 0 else {
    let surfaceID = "surface-\(leafIndex)"
    leafIndex += 1
    return .leaf(surfaceID: surfaceID)
  }

  let deepBranch = makeDeepSplitTree(splitCount: splitCount - 1, leafIndex: &leafIndex)
  let siblingSurfaceID = "surface-\(leafIndex)"
  leafIndex += 1
  let siblingLeaf = TerminalLayoutSnapshotPayload.SnapshotSplitNode.leaf(surfaceID: siblingSurfaceID)
  return .split(direction: .vertical, ratio: 0.5, children: [deepBranch, siblingLeaf])
}
