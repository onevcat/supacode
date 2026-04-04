// supacodeTests/OpenCommandHandlerTests.swift
// Unit tests for OpenCommandHandler — contract-aligned.

import Foundation
import Testing

@testable import supacode

struct OpenCommandHandlerTests {

  // MARK: - Helpers

  private func makeHandler(
    resolver: @escaping OpenCommandHandler.Resolver = { _ in
      OpenResolverResult(
        resolution: .noArgument, worktreeID: nil, worktreeName: nil,
        worktreePath: nil, rootPath: nil, worktreeKind: nil, resolvedPath: nil
      )
    },
    selectWorktree: @escaping OpenCommandHandler.SelectAction = { _ in },
    addAndOpen: @escaping OpenCommandHandler.AddAndOpenAction = { _ in },
    createTabAtPath: @escaping OpenCommandHandler.CreateTabAtPathAction = { _, _ in },
    terminalSnapshot: @escaping OpenCommandHandler.TerminalSnapshotProvider = { _ in nil }
  ) -> OpenCommandHandler {
    OpenCommandHandler(
      resolver: resolver,
      selectWorktree: selectWorktree,
      addAndOpen: addAndOpen,
      createTabAtPath: createTabAtPath,
      terminalSnapshot: terminalSnapshot
    )
  }

  // MARK: - Bring to front (no path)

  @MainActor
  @Test func openWithNoPathReturnsBringToFront() async throws {
    let handler = makeHandler()
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(response.command == "open")
    #expect(response.schemaVersion == "prowl.cli.open.v1")

    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.resolution == "no-argument")
    #expect(payload.invocation == "bare")
    #expect(payload.requestedPath == nil)
    #expect(payload.resolvedPath == nil)
    #expect(payload.broughtToFront == true)
    #expect(payload.appLaunched == false)
    #expect(payload.target == nil)
  }

  // MARK: - Exact root

  @MainActor
  @Test func openExactRootSelectsAndReturnsContractPayload() async throws {
    var selectedID: String?

    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .exactRoot,
          worktreeID: "Prowl:/Users/test/Projects/Prowl",
          worktreeName: "Prowl",
          worktreePath: "/Users/test/Projects/Prowl",
          rootPath: "/Users/test/Projects/Prowl",
          worktreeKind: "git",
          resolvedPath: "/Users/test/Projects/Prowl"
        )
      },
      selectWorktree: { id in selectedID = id },
      terminalSnapshot: { _ in
        OpenTerminalSnapshot(
          tabID: "0E2A7C03-9C01-4BC1-9327-6C1C7B629A52",
          tabTitle: "Prowl 1",
          tabCwd: "/Users/test/Projects/Prowl",
          paneID: "0FB4DDB4-A797-4315-A00E-8AAFB32BFC95",
          paneTitle: "Prowl",
          paneCwd: "/Users/test/Projects/Prowl"
        )
      }
    )

    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/Users/test/Projects/Prowl", invocation: "open-subcommand"))
    )
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(selectedID == "Prowl:/Users/test/Projects/Prowl")

    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.resolution == "exact-root")
    #expect(payload.invocation == "open-subcommand")
    #expect(payload.requestedPath == "/Users/test/Projects/Prowl")
    #expect(payload.resolvedPath == "/Users/test/Projects/Prowl")
    #expect(payload.createdTab == false)
    #expect(payload.broughtToFront == true)

    let target = try #require(payload.target)
    #expect(target.worktree.id == "Prowl:/Users/test/Projects/Prowl")
    #expect(target.worktree.name == "Prowl")
    #expect(target.worktree.kind == "git")
    #expect(target.tab?.id == "0E2A7C03-9C01-4BC1-9327-6C1C7B629A52")
    #expect(target.pane?.id == "0FB4DDB4-A797-4315-A00E-8AAFB32BFC95")
  }

  // MARK: - Inside root

  @MainActor
  @Test func openInsideRootSelectsWorktreeAndCreatesTab() async throws {
    var selectedID: String?
    var tabCreatedForWorktree: String?
    var tabCreatedAtPath: String?

    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .insideRoot,
          worktreeID: "Prowl:/Users/test/Projects/Prowl",
          worktreeName: "Prowl",
          worktreePath: "/Users/test/Projects/Prowl",
          rootPath: "/Users/test/Projects/Prowl",
          worktreeKind: "git",
          resolvedPath: "/Users/test/Projects/Prowl/supacode"
        )
      },
      selectWorktree: { id in selectedID = id },
      createTabAtPath: { worktreeID, path in
        tabCreatedForWorktree = worktreeID
        tabCreatedAtPath = path
      }
    )

    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/Users/test/Projects/Prowl/supacode", invocation: "implicit-open"))
    )
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(selectedID == "Prowl:/Users/test/Projects/Prowl")
    #expect(tabCreatedForWorktree == "Prowl:/Users/test/Projects/Prowl")
    #expect(tabCreatedAtPath == "/Users/test/Projects/Prowl/supacode")

    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.resolution == "inside-root")
    #expect(payload.invocation == "implicit-open")
    #expect(payload.requestedPath == "/Users/test/Projects/Prowl/supacode")
    #expect(payload.resolvedPath == "/Users/test/Projects/Prowl/supacode")
    #expect(payload.createdTab == true)
  }

  // MARK: - New root

  @MainActor
  @Test func openNewRootCallsAddAndOpen() async throws {
    var addedURL: URL?

    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .newRoot,
          worktreeID: nil, worktreeName: nil,
          worktreePath: nil, rootPath: nil,
          worktreeKind: nil, resolvedPath: "/Users/test/NewProject"
        )
      },
      addAndOpen: { url in addedURL = url }
    )

    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/Users/test/NewProject"))
    )
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(addedURL?.path == "/Users/test/NewProject")

    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.resolution == "new-root")
    #expect(payload.requestedPath == "/Users/test/NewProject")
    #expect(payload.createdTab == true)
    #expect(payload.target == nil)
  }

  // MARK: - Router integration

  @MainActor
  @Test func routerUsesInjectedOpenHandler() async throws {
    let handler = makeHandler()
    let router = CLICommandRouter(openHandler: handler)
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await router.route(envelope)

    #expect(response.ok == true)
    #expect(response.command == "open")
    #expect(response.schemaVersion == "prowl.cli.open.v1")
  }

  // MARK: - Wrong command type

  @MainActor
  @Test func handlerRejectsNonOpenCommand() async {
    let handler = makeHandler()
    let envelope = CommandEnvelope(output: .json, command: .list(ListInput()))
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == false)
    #expect(response.error?.code == "INVALID_ARGUMENT")
  }

  // MARK: - Invocation derivation

  @MainActor
  @Test func defaultInvocationIsBareWhenNoPath() async throws {
    let handler = makeHandler()
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await handler.handle(envelope: envelope)
    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.invocation == "bare")
  }

  @MainActor
  @Test func defaultInvocationIsOpenSubcommandWhenPathPresent() async throws {
    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .newRoot,
          worktreeID: nil, worktreeName: nil,
          worktreePath: nil, rootPath: nil,
          worktreeKind: nil, resolvedPath: "/tmp/test"
        )
      }
    )
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput(path: "/tmp/test")))
    let response = await handler.handle(envelope: envelope)
    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.invocation == "open-subcommand")
  }

  @MainActor
  @Test func explicitInvocationIsPreserved() async throws {
    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .newRoot,
          worktreeID: nil, worktreeName: nil,
          worktreePath: nil, rootPath: nil,
          worktreeKind: nil, resolvedPath: "/tmp/test"
        )
      }
    )
    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/tmp/test", invocation: "implicit-open"))
    )
    let response = await handler.handle(envelope: envelope)
    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.invocation == "implicit-open")
  }

  // MARK: - App launched flag

  @MainActor
  @Test func appLaunchedFlagIsPassedThrough() async throws {
    let handler = makeHandler(
      resolver: { _ in
        OpenResolverResult(
          resolution: .exactRoot,
          worktreeID: "Test:/tmp/project",
          worktreeName: "project",
          worktreePath: "/tmp/project",
          rootPath: "/tmp/project",
          worktreeKind: "git",
          resolvedPath: "/tmp/project"
        )
      }
    )
    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/tmp/project", appLaunched: true))
    )
    let response = await handler.handle(envelope: envelope)
    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.appLaunched == true)
    #expect(payload.broughtToFront == true)
  }

  @MainActor
  @Test func appLaunchedDefaultsToFalse() async throws {
    let handler = makeHandler()
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await handler.handle(envelope: envelope)
    let data = try #require(response.data)
    let payload = try data.decode(as: OpenCommandData.self)
    #expect(payload.appLaunched == false)
  }
}
