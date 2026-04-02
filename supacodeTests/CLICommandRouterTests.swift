// supacodeTests/CLICommandRouterTests.swift
// Unit tests for CLICommandRouter and StubCommandHandler.

import Foundation
import Testing

@testable import supacode

struct CLICommandRouterTests {

  // MARK: - Stub handler returns NOT_IMPLEMENTED

  @MainActor
  @Test func stubHandlerReturnsNotImplemented() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(output: .json, command: .list(ListInput()))
    let response = await router.route(envelope)
    #expect(response.ok == false)
    #expect(response.error?.code == "NOT_IMPLEMENTED")
    #expect(response.command == "list")
  }

  @MainActor
  @Test func routerDispatchesOpenToOpenHandler() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(
      output: .text,
      command: .open(OpenInput(path: "/tmp/test"))
    )
    let response = await router.route(envelope)
    #expect(response.command == "open")
    #expect(response.error?.code == "NOT_IMPLEMENTED")
  }

  @MainActor
  @Test func routerDispatchesSendToSendHandler() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(
      output: .json,
      command: .send(SendInput(text: "hello"))
    )
    let response = await router.route(envelope)
    #expect(response.command == "send")
    #expect(response.error?.code == "NOT_IMPLEMENTED")
  }

  @MainActor
  @Test func routerDispatchesFocusToFocusHandler() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(
      output: .text,
      command: .focus(FocusInput(selector: .pane("p1")))
    )
    let response = await router.route(envelope)
    #expect(response.command == "focus")
  }

  @MainActor
  @Test func routerDispatchesKeyToKeyHandler() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(
      output: .json,
      command: .key(KeyInput(token: "enter", repeatCount: 3))
    )
    let response = await router.route(envelope)
    #expect(response.command == "key")
  }

  @MainActor
  @Test func routerDispatchesReadToReadHandler() async {
    let router = CLICommandRouter()
    let envelope = CommandEnvelope(
      output: .text,
      command: .read(ReadInput(last: 10))
    )
    let response = await router.route(envelope)
    #expect(response.command == "read")
  }

  // MARK: - Custom handler injection

  @MainActor
  @Test func routerUsesInjectedHandler() async {
    let customHandler = MockCommandHandler(
      response: CommandResponse(
        ok: true,
        command: "list",
        schemaVersion: "prowl.cli.list.v1"
      )
    )
    let router = CLICommandRouter(listHandler: customHandler)
    let envelope = CommandEnvelope(output: .json, command: .list(ListInput()))
    let response = await router.route(envelope)
    #expect(response.ok == true)
    #expect(response.command == "list")
  }

  // MARK: - Schema version format

  @MainActor
  @Test func stubSchemaVersionFollowsConvention() async {
    let commands: [Command] = [
      .open(OpenInput()),
      .list(ListInput()),
      .focus(FocusInput()),
      .send(SendInput(text: "x")),
      .key(KeyInput(token: "tab")),
      .read(ReadInput()),
    ]
    let router = CLICommandRouter()
    for cmd in commands {
      let envelope = CommandEnvelope(output: .json, command: cmd)
      let response = await router.route(envelope)
      #expect(response.schemaVersion.hasPrefix("prowl.cli."))
      #expect(response.schemaVersion.hasSuffix(".v1"))
    }
  }
}

// MARK: - Test helpers

private struct MockCommandHandler: CommandHandler {
  let response: CommandResponse

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    response
  }
}
