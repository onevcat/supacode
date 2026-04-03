// supacode/CLIService/TargetResolver.swift
// Resolves target selectors against current app state.

import Foundation
import GhosttyKit

/// Fully resolved target with metadata for response payload.
struct ResolvedTarget: Sendable {
  let worktreeID: String
  let worktreeName: String
  let worktreePath: String
  let worktreeRootPath: String
  let worktreeKind: ListCommandWorktree.Kind

  let tabID: UUID
  let tabTitle: String
  let tabSelected: Bool

  let paneID: UUID
  let paneTitle: String
  let paneCWD: String?
  let paneFocused: Bool

  let surfaceView: GhosttySurfaceView
}

enum TargetResolverError: Error {
  case notFound(String)
  case notUnique(String)
}

@MainActor
final class TargetResolver {
  typealias SnapshotProvider = @MainActor () -> TargetResolutionSnapshot

  private let snapshotProvider: SnapshotProvider

  init(snapshotProvider: @escaping SnapshotProvider) {
    self.snapshotProvider = snapshotProvider
  }

  func resolve(_ selector: TargetSelector) -> Result<ResolvedTarget, TargetResolverError> {
    let snapshot = snapshotProvider()
    switch selector {
    case .none:
      return resolveNone(snapshot)
    case .worktree(let value):
      return resolveWorktree(value, snapshot)
    case .tab(let value):
      return resolveTab(value, snapshot)
    case .pane(let value):
      return resolvePane(value, snapshot)
    }
  }

  // MARK: - .none: focused worktree → selected tab → focused pane

  private func resolveNone(_ snapshot: TargetResolutionSnapshot) -> Result<ResolvedTarget, TargetResolverError> {
    guard let focusedWorktreeID = snapshot.focusedWorktreeID else {
      return .failure(.notFound("No focused worktree."))
    }
    guard let worktree = snapshot.worktrees.first(where: { $0.id == focusedWorktreeID }) else {
      return .failure(.notFound("Focused worktree not found."))
    }
    guard let tab = worktree.tabs.first(where: { $0.selected }) else {
      return .failure(.notFound("No selected tab in focused worktree."))
    }
    guard let pane = tab.focusedPane else {
      return .failure(.notFound("No focused pane in selected tab."))
    }
    return .success(makeTarget(worktree: worktree, tab: tab, pane: pane, focusedWorktreeID: focusedWorktreeID))
  }

  // MARK: - .worktree: match by id, name, or path

  private func resolveWorktree(
    _ value: String,
    _ snapshot: TargetResolutionSnapshot
  ) -> Result<ResolvedTarget, TargetResolverError> {
    let matches = snapshot.worktrees.filter { worktree in
      worktree.id == value || worktree.name == value || worktree.path == value
    }
    guard !matches.isEmpty else {
      return .failure(.notFound("Worktree '\(value)' not found."))
    }
    guard matches.count == 1 else {
      return .failure(.notUnique("Worktree '\(value)' matches \(matches.count) worktrees."))
    }
    let worktree = matches[0]
    guard let tab = worktree.tabs.first(where: { $0.selected }) ?? worktree.tabs.first else {
      return .failure(.notFound("No tabs in worktree '\(value)'."))
    }
    guard let pane = tab.focusedPane ?? tab.panes.first else {
      return .failure(.notFound("No panes in worktree '\(value)'."))
    }
    return .success(makeTarget(worktree: worktree, tab: tab, pane: pane, focusedWorktreeID: snapshot.focusedWorktreeID))
  }

  // MARK: - .tab: find by UUID

  private func resolveTab(
    _ value: String,
    _ snapshot: TargetResolutionSnapshot
  ) -> Result<ResolvedTarget, TargetResolverError> {
    guard let uuid = UUID(uuidString: value) else {
      return .failure(.notFound("Invalid tab UUID: '\(value)'."))
    }
    for worktree in snapshot.worktrees {
      for tab in worktree.tabs where tab.id == uuid {
        guard let pane = tab.focusedPane ?? tab.panes.first else {
          return .failure(.notFound("No panes in tab '\(value)'."))
        }
        return .success(
          makeTarget(
            worktree: worktree,
            tab: tab,
            pane: pane,
            focusedWorktreeID: snapshot.focusedWorktreeID
          ))
      }
    }
    return .failure(.notFound("Tab '\(value)' not found."))
  }

  // MARK: - .pane: find by UUID across all worktrees/tabs

  private func resolvePane(
    _ value: String,
    _ snapshot: TargetResolutionSnapshot
  ) -> Result<ResolvedTarget, TargetResolverError> {
    guard let uuid = UUID(uuidString: value) else {
      return .failure(.notFound("Invalid pane UUID: '\(value)'."))
    }
    for worktree in snapshot.worktrees {
      for tab in worktree.tabs {
        for pane in tab.panes where pane.id == uuid {
          return .success(
            makeTarget(
              worktree: worktree,
              tab: tab,
              pane: pane,
              focusedWorktreeID: snapshot.focusedWorktreeID
            ))
        }
      }
    }
    return .failure(.notFound("Pane '\(value)' not found."))
  }

  // MARK: - Helpers

  private func makeTarget(
    worktree: TargetResolutionSnapshot.Worktree,
    tab: TargetResolutionSnapshot.Tab,
    pane: TargetResolutionSnapshot.Pane,
    focusedWorktreeID: String?
  ) -> ResolvedTarget {
    let isFocusedWorktree = worktree.id == focusedWorktreeID
    return ResolvedTarget(
      worktreeID: worktree.id,
      worktreeName: worktree.name,
      worktreePath: worktree.path,
      worktreeRootPath: worktree.rootPath,
      worktreeKind: worktree.kind,
      tabID: tab.id,
      tabTitle: tab.title,
      tabSelected: tab.selected,
      paneID: pane.id,
      paneTitle: pane.title,
      paneCWD: pane.cwd,
      paneFocused: isFocusedWorktree && tab.selected && pane.isFocusedInTab,
      surfaceView: pane.surfaceView
    )
  }
}

// MARK: - Snapshot model (decouples from live state)

struct TargetResolutionSnapshot: Sendable {
  struct Worktree: Sendable {
    let id: String
    let name: String
    let path: String
    let rootPath: String
    let kind: ListCommandWorktree.Kind
    let tabs: [Tab]
  }

  struct Tab: Sendable {
    let id: UUID
    let title: String
    let selected: Bool
    let panes: [Pane]
    let focusedPaneID: UUID?

    var focusedPane: Pane? {
      guard let focusedPaneID else { return nil }
      return panes.first { $0.id == focusedPaneID }
    }
  }

  struct Pane: @unchecked Sendable {
    let id: UUID
    let title: String
    let cwd: String?
    let isFocusedInTab: Bool
    let surfaceView: GhosttySurfaceView
  }

  let worktrees: [Worktree]
  let focusedWorktreeID: String?
}

// MARK: - Snapshot builder

@MainActor
enum TargetResolutionSnapshotBuilder {
  static func makeSnapshot(
    repositoriesState: RepositoriesFeature.State,
    terminalManager: WorktreeTerminalManager
  ) -> TargetResolutionSnapshot {
    let activeSnapshots = Dictionary(
      uniqueKeysWithValues: terminalManager.activeWorktreeStates.map {
        ($0.worktreeID, $0)
      }
    )

    let orderedContexts = ListRuntimeSnapshotBuilder.orderedWorktreeContexts(from: repositoriesState)
    let focusedWorktreeID = terminalManager.selectedWorktreeID ?? terminalManager.canvasFocusedWorktreeID

    let worktrees: [TargetResolutionSnapshot.Worktree] = orderedContexts.compactMap { context in
      guard let state = activeSnapshots[context.id] else { return nil }
      let selectedTabID = state.tabManager.selectedTabId
      let tabs: [TargetResolutionSnapshot.Tab] = state.tabManager.tabs.compactMap { tab in
        let snapshot = state.makeCLISendSnapshot(for: tab.id)
        guard let snapshot else { return nil }
        return TargetResolutionSnapshot.Tab(
          id: tab.id.rawValue,
          title: tab.title,
          selected: tab.id == selectedTabID,
          panes: snapshot.panes,
          focusedPaneID: snapshot.focusedPaneID
        )
      }
      guard !tabs.isEmpty else { return nil }
      return TargetResolutionSnapshot.Worktree(
        id: context.id,
        name: context.name,
        path: context.path,
        rootPath: context.rootPath,
        kind: context.kind,
        tabs: tabs
      )
    }

    return TargetResolutionSnapshot(worktrees: worktrees, focusedWorktreeID: focusedWorktreeID)
  }
}
