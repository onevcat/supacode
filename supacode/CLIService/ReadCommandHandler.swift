// supacode/CLIService/ReadCommandHandler.swift
// Handles `prowl read` by resolving target and reading snapshot/last text.

import Foundation

private struct ReadCapture {
  let text: String
  let source: ReadSource
  let truncated: Bool
}

struct ReadCaptureInput: Sendable {
  let viewportText: String
  let screenText: String?
}

/// Resolved target metadata for read payload construction.
struct ReadResolvedTarget: Sendable {
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

extension ReadResolvedTarget {
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
final class ReadCommandHandler: CommandHandler {
  typealias ResolveProvider = @MainActor (TargetSelector) -> Result<ReadResolvedTarget, TargetResolverError>
  typealias CaptureProvider = @MainActor (ReadResolvedTarget) -> ReadCaptureInput?

  private let resolveProvider: ResolveProvider
  private let captureProvider: CaptureProvider

  init(
    resolveProvider: @escaping ResolveProvider,
    captureProvider: @escaping CaptureProvider
  ) {
    self.resolveProvider = resolveProvider
    self.captureProvider = captureProvider
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .read(let input) = envelope.command else {
      return errorResponse(code: CLIErrorCode.readFailed, message: "Invalid command.")
    }

    let target: ReadResolvedTarget
    switch resolveProvider(input.selector) {
    case .success(let resolved):
      target = resolved
    case .failure(let error):
      return mapResolverError(error)
    }

    guard let captureInput = captureProvider(target) else {
      return errorResponse(code: CLIErrorCode.readFailed, message: "Failed to read terminal text.")
    }

    let capture: ReadCapture
    if let last = input.last {
      capture = captureLast(
        requestedLineCount: last,
        viewportText: captureInput.viewportText,
        screenText: captureInput.screenText
      )
    } else {
      capture = ReadCapture(
        text: captureInput.viewportText,
        source: .screen,
        truncated: false
      )
    }

    let payload = ReadCommandPayload(
      target: makePayloadTarget(from: target),
      mode: input.last == nil ? .snapshot : .last,
      last: input.last,
      source: capture.source,
      truncated: capture.truncated,
      lineCount: lineCount(in: capture.text),
      text: capture.text
    )

    do {
      return try CommandResponse(
        ok: true,
        command: "read",
        schemaVersion: "prowl.cli.read.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return errorResponse(code: CLIErrorCode.readFailed, message: "Failed to encode response.")
    }
  }

  private func captureLast(
    requestedLineCount: Int,
    viewportText: String,
    screenText: String?
  ) -> ReadCapture {
    let viewportLines = splitLines(viewportText)
    if viewportLines.count >= requestedLineCount {
      let text = joinLines(viewportLines.suffix(requestedLineCount))
      return ReadCapture(
        text: text,
        source: .screen,
        truncated: false
      )
    }

    guard let screenText else {
      return ReadCapture(
        text: joinLines(viewportLines.suffix(min(requestedLineCount, viewportLines.count))),
        source: .mixed,
        truncated: viewportLines.count < requestedLineCount
      )
    }

    let screenLines = splitLines(screenText)
    if screenLines.count < viewportLines.count {
      return ReadCapture(
        text: joinLines(viewportLines.suffix(min(requestedLineCount, viewportLines.count))),
        source: .mixed,
        truncated: viewportLines.count < requestedLineCount
      )
    }

    let source: ReadSource = screenLines.count > viewportLines.count ? .scrollback : .screen
    let text = joinLines(screenLines.suffix(min(requestedLineCount, screenLines.count)))

    return ReadCapture(
      text: text,
      source: source,
      truncated: screenLines.count < requestedLineCount
    )
  }

  private func splitLines(_ text: String) -> [Substring] {
    guard !text.isEmpty else { return [] }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
  }

  private func joinLines(_ lines: ArraySlice<Substring>) -> String {
    lines.map(String.init).joined(separator: "\n")
  }

  private func lineCount(in text: String) -> Int {
    splitLines(text).count
  }

  private func makePayloadTarget(from target: ReadResolvedTarget) -> ReadTarget {
    ReadTarget(
      worktree: ReadTargetWorktree(
        id: target.worktreeID,
        name: target.worktreeName,
        path: target.worktreePath,
        rootPath: target.worktreeRootPath,
        kind: target.worktreeKind.rawValue
      ),
      tab: ReadTargetTab(
        id: target.tabID.uuidString,
        title: target.tabTitle,
        selected: target.tabSelected
      ),
      pane: ReadTargetPane(
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
      command: "read",
      schemaVersion: "prowl.cli.read.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
