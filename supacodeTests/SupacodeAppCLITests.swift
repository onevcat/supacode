import ComposableArchitecture
import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct SupacodeAppCLITests {
  @Test func cliRouterWiresKeyAndReadHandlersInsteadOfStubHandlers() async {
    let store = Store(initialState: AppFeature.State()) {
      AppFeature()
    }
    let terminalManager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let router = SupacodeApp.makeCLICommandRouter(appStore: store, terminalManager: terminalManager)

    let keyResponse = await router.route(
      CommandEnvelope(output: .json, command: .key(KeyInput(rawToken: "enter", token: "enter")))
    )
    let readResponse = await router.route(
      CommandEnvelope(output: .json, command: .read(ReadInput()))
    )

    #expect(keyResponse.command == "key")
    #expect(readResponse.command == "read")
    #expect(keyResponse.error?.code != "NOT_IMPLEMENTED")
    #expect(readResponse.error?.code != "NOT_IMPLEMENTED")
  }

  @Test func resolveCLITerminalWorktreeBuildsSyntheticRunnableFolderWorktree() {
    let repository = Repository(
      id: "/Users/test/PlainFolder",
      rootURL: URL(fileURLWithPath: "/Users/test/PlainFolder", isDirectory: true),
      name: "PlainFolder",
      kind: .plain,
      worktrees: []
    )

    let resolved = SupacodeApp.resolveCLITerminalWorktree(
      id: repository.id,
      repositories: [repository]
    )

    #expect(resolved?.id == repository.id)
    #expect(resolved?.name == "PlainFolder")
    #expect(
      resolved?.workingDirectory.standardizedFileURL.path(percentEncoded: false)
        == URL(fileURLWithPath: "/Users/test/PlainFolder", isDirectory: true)
        .standardizedFileURL.path(percentEncoded: false)
    )
  }
}
