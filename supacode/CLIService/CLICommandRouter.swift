// supacode/CLIService/CLICommandRouter.swift
// Routes incoming command envelopes to the appropriate handler.

import Foundation

@MainActor
final class CLICommandRouter {
  private let openHandler: any CommandHandler
  private let listHandler: any CommandHandler
  private let focusHandler: any CommandHandler
  private let sendHandler: any CommandHandler
  private let keyHandler: any CommandHandler
  private let readHandler: any CommandHandler

  init(
    openHandler: any CommandHandler = StubCommandHandler(command: "open"),
    listHandler: any CommandHandler = StubCommandHandler(command: "list"),
    focusHandler: any CommandHandler = StubCommandHandler(command: "focus"),
    sendHandler: any CommandHandler = StubCommandHandler(command: "send"),
    keyHandler: any CommandHandler = StubCommandHandler(command: "key"),
    readHandler: any CommandHandler = StubCommandHandler(command: "read")
  ) {
    self.openHandler = openHandler
    self.listHandler = listHandler
    self.focusHandler = focusHandler
    self.sendHandler = sendHandler
    self.keyHandler = keyHandler
    self.readHandler = readHandler
  }

  func route(_ envelope: CommandEnvelope) async -> CommandResponse {
    let handler: any CommandHandler
    switch envelope.command {
    case .open: handler = openHandler
    case .list: handler = listHandler
    case .focus: handler = focusHandler
    case .send: handler = sendHandler
    case .key: handler = keyHandler
    case .read: handler = readHandler
    }
    return await handler.handle(envelope: envelope)
  }
}

// MARK: - Stub handler (placeholder until real handlers are implemented)

struct StubCommandHandler: CommandHandler {
  let command: String

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    CommandResponse(
      ok: false,
      command: command,
      schemaVersion: "prowl.cli.\(command).v1",
      error: CommandError(
        code: "NOT_IMPLEMENTED",
        message: "Command '\(command)' is not yet implemented."
      )
    )
  }
}
