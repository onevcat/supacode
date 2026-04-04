// supacode/CLIService/OpenCommandHandler.swift
// Handles `prowl open [path]` — resolves path to worktree, selects it, brings app to front.
// Response payload follows doc-onevcat/contracts/cli/open.md contract.

import AppKit
import Foundation

// MARK: - Resolution

/// How the requested path was resolved against current app state.
enum OpenResolution: String, Sendable, Codable {
  /// Bare `prowl` with no path.
  case noArgument = "no-argument"
  /// Path matched an already-open root exactly.
  case exactRoot = "exact-root"
  /// Path was inside an already-open root.
  case insideRoot = "inside-root"
  /// Path was not yet managed; Prowl opened it as a new root.
  case newRoot = "new-root"
}

/// Internal result of resolving an open command against current app state.
struct OpenResolverResult: Sendable {
  let resolution: OpenResolution
  let worktreeID: String?
  let worktreeName: String?
  let worktreePath: String?
  let rootPath: String?
  let worktreeKind: String?
  let resolvedPath: String?
}

// MARK: - Contract-aligned payload

/// Success payload per doc-onevcat/contracts/cli/open.md
struct OpenCommandData: Codable {
  let invocation: String
  let requestedPath: String?
  let resolvedPath: String?
  let resolution: String
  let appLaunched: Bool
  let broughtToFront: Bool
  let createdTab: Bool
  let target: OpenTarget?

  enum CodingKeys: String, CodingKey {
    case invocation
    case requestedPath = "requested_path"
    case resolvedPath = "resolved_path"
    case resolution
    case appLaunched = "app_launched"
    case broughtToFront = "brought_to_front"
    case createdTab = "created_tab"
    case target
  }
}

struct OpenTarget: Codable {
  let worktree: OpenTargetWorktree
  let tab: OpenTargetTab?
  let pane: OpenTargetPane?
}

struct OpenTargetWorktree: Codable {
  let id: String
  let name: String
  let path: String
  let rootPath: String
  let kind: String

  enum CodingKeys: String, CodingKey {
    case id, name, path
    case rootPath = "root_path"
    case kind
  }
}

struct OpenTargetTab: Codable {
  let id: String
  let title: String
  let cwd: String?
}

struct OpenTargetPane: Codable {
  let id: String
  let title: String
  let cwd: String?
}

// MARK: - Terminal snapshot for open command

struct OpenTerminalSnapshot: Sendable {
  let tabID: String?
  let tabTitle: String?
  let tabCwd: String?
  let paneID: String?
  let paneTitle: String?
  let paneCwd: String?
}

// MARK: - Handler

final class OpenCommandHandler: CommandHandler {
  typealias Resolver = @MainActor (String?) -> OpenResolverResult
  typealias SelectAction = @MainActor (String) -> Void
  typealias AddAndOpenAction = @MainActor (URL) -> Void
  /// Creates a new tab in the given worktree and `cd`s to the specified path.
  /// Parameters: worktreeID, absolutePath.
  typealias CreateTabAtPathAction = @MainActor (String, String) -> Void
  typealias TerminalSnapshotProvider = @MainActor (String) -> OpenTerminalSnapshot?
  /// Returns when app state is ready for command execution (repositories loaded).
  typealias ReadinessWaiter = @MainActor () async -> Void

  private let resolver: Resolver
  private let selectWorktree: SelectAction
  private let addAndOpen: AddAndOpenAction
  private let createTabAtPath: CreateTabAtPathAction
  private let terminalSnapshot: TerminalSnapshotProvider
  private let waitForReady: ReadinessWaiter

  init(
    resolver: @escaping Resolver,
    selectWorktree: @escaping SelectAction,
    addAndOpen: @escaping AddAndOpenAction,
    createTabAtPath: @escaping CreateTabAtPathAction = { _, _ in },
    terminalSnapshot: @escaping TerminalSnapshotProvider,
    waitForReady: @escaping ReadinessWaiter = {}
  ) {
    self.resolver = resolver
    self.selectWorktree = selectWorktree
    self.addAndOpen = addAndOpen
    self.createTabAtPath = createTabAtPath
    self.terminalSnapshot = terminalSnapshot
    self.waitForReady = waitForReady
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .open(let input) = envelope.command else {
      return CommandResponse(
        ok: false,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        error: CommandError(code: CLIErrorCode.invalidArgument, message: "Expected open command.")
      )
    }

    let appLaunched = input.appLaunched

    // When the app was just launched by this CLI command, wait for
    // repositories to finish loading before resolving the path.
    if appLaunched {
      await waitForReady()
    }

    let result = resolver(input.path)
    let invocation = deriveInvocation(input: input)

    switch result.resolution {
    case .noArgument:
      bringAppToFront()
      return makeSuccess(
        invocation: invocation,
        requestedPath: nil,
        resolvedPath: nil,
        resolution: .noArgument,
        appLaunched: appLaunched,
        createdTab: false,
        target: nil
      )

    case .exactRoot:
      if let worktreeID = result.worktreeID {
        selectWorktree(worktreeID)
      }
      bringAppToFront()
      let snapshot = result.worktreeID.flatMap { terminalSnapshot($0) }
      return makeSuccess(
        invocation: invocation,
        requestedPath: input.path,
        resolvedPath: result.resolvedPath ?? input.path,
        resolution: .exactRoot,
        appLaunched: appLaunched,
        createdTab: false,
        target: makeTarget(result: result, snapshot: snapshot)
      )

    case .insideRoot:
      if let worktreeID = result.worktreeID {
        selectWorktree(worktreeID)
        // Open a new tab cd'd to the exact requested subpath.
        if let subpath = result.resolvedPath ?? input.path {
          createTabAtPath(worktreeID, subpath)
        }
      }
      bringAppToFront()
      let snapshot = result.worktreeID.flatMap { terminalSnapshot($0) }
      return makeSuccess(
        invocation: invocation,
        requestedPath: input.path,
        resolvedPath: result.resolvedPath ?? input.path,
        resolution: .insideRoot,
        appLaunched: appLaunched,
        createdTab: true,
        target: makeTarget(result: result, snapshot: snapshot)
      )

    case .newRoot:
      if let path = result.resolvedPath ?? input.path {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        addAndOpen(url)
      }
      bringAppToFront()
      return makeSuccess(
        invocation: invocation,
        requestedPath: input.path,
        resolvedPath: result.resolvedPath ?? input.path,
        resolution: .newRoot,
        appLaunched: appLaunched,
        createdTab: true,
        target: nil
      )
    }
  }

  // MARK: - Private

  private func deriveInvocation(input: OpenInput) -> String {
    if let inv = input.invocation {
      return inv
    }
    return input.path == nil ? "bare" : "open-subcommand"
  }

  private func bringAppToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func makeTarget(
    result: OpenResolverResult,
    snapshot: OpenTerminalSnapshot?
  ) -> OpenTarget? {
    guard let worktreeID = result.worktreeID,
          let worktreeName = result.worktreeName,
          let worktreePath = result.worktreePath,
          let rootPath = result.rootPath
    else {
      return nil
    }

    let worktreeTarget = OpenTargetWorktree(
      id: worktreeID,
      name: worktreeName,
      path: worktreePath,
      rootPath: rootPath,
      kind: result.worktreeKind ?? "git"
    )

    let tabTarget: OpenTargetTab? = snapshot.flatMap { snap in
      guard let tabID = snap.tabID, let tabTitle = snap.tabTitle else { return nil }
      return OpenTargetTab(id: tabID, title: tabTitle, cwd: snap.tabCwd)
    }

    let paneTarget: OpenTargetPane? = snapshot.flatMap { snap in
      guard let paneID = snap.paneID, let paneTitle = snap.paneTitle else { return nil }
      return OpenTargetPane(id: paneID, title: paneTitle, cwd: snap.paneCwd)
    }

    return OpenTarget(worktree: worktreeTarget, tab: tabTarget, pane: paneTarget)
  }

  // swiftlint:disable:next function_parameter_count
  private func makeSuccess(
    invocation: String,
    requestedPath: String?,
    resolvedPath: String?,
    resolution: OpenResolution,
    appLaunched: Bool,
    createdTab: Bool,
    target: OpenTarget?
  ) -> CommandResponse {
    let payload = OpenCommandData(
      invocation: invocation,
      requestedPath: requestedPath,
      resolvedPath: resolvedPath,
      resolution: resolution.rawValue,
      appLaunched: appLaunched,
      broughtToFront: true,
      createdTab: createdTab,
      target: target
    )
    do {
      return try CommandResponse(
        ok: true,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return CommandResponse(
        ok: false,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        error: CommandError(
          code: CLIErrorCode.openFailed,
          message: "Failed to encode response."
        )
      )
    }
  }
}
