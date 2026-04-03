// supacode/CLIService/SendCommandHandler.swift
// Handles `prowl send` by resolving target, delivering text, and optionally waiting.

import Foundation

private let sendLogger = SupaLogger("SendCommandHandler")

/// Resolved target metadata for payload construction (no live view reference).
struct SendResolvedTarget: Sendable {
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
}

extension SendResolvedTarget {
  init(from resolved: ResolvedTarget) {
    self.worktreeID = resolved.worktreeID
    self.worktreeName = resolved.worktreeName
    self.worktreePath = resolved.worktreePath
    self.worktreeRootPath = resolved.worktreeRootPath
    self.worktreeKind = resolved.worktreeKind
    self.tabID = resolved.tabID
    self.tabTitle = resolved.tabTitle
    self.tabSelected = resolved.tabSelected
    self.paneID = resolved.paneID
    self.paneTitle = resolved.paneTitle
    self.paneCWD = resolved.paneCWD
    self.paneFocused = resolved.paneFocused
  }
}

@MainActor
struct CLISendTextDelivery {
  typealias InsertText = @MainActor (UUID, String) -> Bool
  typealias SubmitLine = @MainActor (UUID) -> Bool

  let insertText: InsertText
  let submitLine: SubmitLine

  func deliver(to target: SendResolvedTarget, text: String, trailingEnter: Bool) {
    _ = insertText(target.paneID, text)
    if trailingEnter {
      _ = submitLine(target.paneID)
    }
  }
}

@MainActor
final class SendCommandHandler: CommandHandler {
  typealias ResolveProvider = @MainActor (TargetSelector) -> Result<SendResolvedTarget, TargetResolverError>
  typealias TextDelivery = @MainActor (SendResolvedTarget, String, Bool) -> Void
  typealias WaiterProvider = @MainActor (String, UUID) -> AsyncStream<(exitCode: Int?, durationMs: Int)>?

  private let resolveProvider: ResolveProvider
  private let textDelivery: TextDelivery
  private let waiterProvider: WaiterProvider

  init(
    resolveProvider: @escaping ResolveProvider,
    textDelivery: @escaping TextDelivery,
    waiterProvider: @escaping WaiterProvider
  ) {
    self.resolveProvider = resolveProvider
    self.textDelivery = textDelivery
    self.waiterProvider = waiterProvider
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .send(let input) = envelope.command else {
      return errorResponse(code: CLIErrorCode.sendFailed, message: "Invalid command.")
    }

    // Resolve target
    let result = resolveProvider(input.selector)
    let target: SendResolvedTarget
    switch result {
    case .success(let resolved):
      target = resolved
    case .failure(let error):
      return mapResolverError(error)
    }

    let waitStream = input.wait ? waiterProvider(target.worktreeID, target.paneID) : nil

    // Deliver text (and optional Enter)
    textDelivery(target, input.text, input.trailingEnter)

    // Wait for command completion if requested
    let waitResult: SendWaitResult?
    if input.wait {
      waitResult = await waitForCompletion(
        stream: waitStream,
        timeoutSeconds: input.timeoutSeconds ?? 30
      )
      if waitResult == nil {
        return errorResponse(
          code: CLIErrorCode.waitTimeout,
          message: "Timed out waiting for command to finish. "
            + "This may happen if the terminal does not have shell integration (OSC 133) enabled."
        )
      }
    } else {
      waitResult = nil
    }

    // Build payload
    let payload = SendCommandPayload(
      target: makePayloadTarget(from: target),
      input: SendInputInfo(
        source: input.source.rawValue,
        characters: input.text.unicodeScalars.count,
        bytes: input.text.utf8.count,
        trailingEnterSent: input.trailingEnter
      ),
      createdTab: false,
      wait: waitResult
    )

    do {
      return try CommandResponse(
        ok: true,
        command: "send",
        schemaVersion: "prowl.cli.send.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      sendLogger.warning("Failed to encode send payload: \(error)")
      return errorResponse(code: CLIErrorCode.sendFailed, message: "Failed to encode response.")
    }
  }

  // MARK: - Wait

  private func waitForCompletion(
    stream: AsyncStream<(exitCode: Int?, durationMs: Int)>?,
    timeoutSeconds: Int
  ) async -> SendWaitResult? {
    guard let stream else {
      return nil
    }

    // Race stream result against timeout using raw tuples (Sendable-safe).
    let raw: (exitCode: Int?, durationMs: Int)? = await withTaskGroup(
      of: (Int?, Int)?.self
    ) { group in
      group.addTask {
        for await result in stream {
          return (result.exitCode, result.durationMs)
        }
        return nil
      }

      group.addTask {
        try? await Task.sleep(for: .seconds(timeoutSeconds))
        return nil
      }

      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }

    guard let raw else { return nil }
    return SendWaitResult(exitCode: raw.exitCode, durationMs: raw.durationMs)
  }

  // MARK: - Helpers

  private func makePayloadTarget(from target: SendResolvedTarget) -> SendTarget {
    SendTarget(
      worktree: SendTargetWorktree(
        id: target.worktreeID,
        name: target.worktreeName,
        path: target.worktreePath,
        rootPath: target.worktreeRootPath,
        kind: target.worktreeKind.rawValue
      ),
      tab: SendTargetTab(
        id: target.tabID.uuidString,
        title: target.tabTitle,
        selected: target.tabSelected
      ),
      pane: SendTargetPane(
        id: target.paneID.uuidString,
        title: target.paneTitle,
        cwd: target.paneCWD,
        focused: target.paneFocused
      )
    )
  }

  private func mapResolverError(_ error: TargetResolverError) -> CommandResponse {
    switch error {
    case .notFound(let message):
      return errorResponse(code: CLIErrorCode.targetNotFound, message: message)
    case .notUnique(let message):
      return errorResponse(code: CLIErrorCode.targetNotUnique, message: message)
    }
  }

  private func errorResponse(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "send",
      schemaVersion: "prowl.cli.send.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
