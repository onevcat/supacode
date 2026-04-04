import Foundation
import Testing

@testable import supacode

@MainActor
struct CLIReadCommandHandlerTests {
  private static let paneID = UUID(uuidString: "6E1A2A10-D99F-4E3F-920C-D93AA3C05764")!
  private static let tabID = UUID(uuidString: "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0")!

  private static func makeTarget() -> ReadResolvedTarget {
    ReadResolvedTarget(
      worktreeID: "Prowl:/Users/onevcat/Projects/Prowl",
      worktreeName: "Prowl",
      worktreePath: "/Users/onevcat/Projects/Prowl",
      worktreeRootPath: "/Users/onevcat/Projects/Prowl",
      worktreeKind: .git,
      tabID: tabID,
      tabTitle: "Prowl 1",
      tabSelected: true,
      paneID: paneID,
      paneTitle: "zsh",
      paneCWD: "/Users/onevcat/Projects/Prowl",
      paneFocused: true
    )
  }

  private static func makeEnvelope(last: Int? = nil) -> CommandEnvelope {
    CommandEnvelope(
      output: .json,
      command: .read(ReadInput(selector: .none, last: last))
    )
  }

  @Test func snapshotUsesViewportText() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "line-1\nline-2",
          screenText: "old\nline-1\nline-2"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    #expect(response.command == "read")
    #expect(response.schemaVersion == "prowl.cli.read.v1")
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.mode == .snapshot)
    #expect(payload.last == nil)
    #expect(payload.source == .screen)
    #expect(payload.truncated == false)
    #expect(payload.lineCount == 2)
    #expect(payload.text == "line-1\nline-2")
  }

  @Test func snapshotSucceedsWhenScreenCaptureUnavailable() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "line-1\nline-2",
          screenText: nil
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.mode == .snapshot)
    #expect(payload.source == .screen)
    #expect(payload.truncated == false)
    #expect(payload.lineCount == 2)
    #expect(payload.text == "line-1\nline-2")
  }

  @Test func lastUsesViewportWhenEnoughLines() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "a\nb\nc\nd",
          screenText: "x\na\nb\nc\nd"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 2))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.mode == .last)
    #expect(payload.last == 2)
    #expect(payload.source == .screen)
    #expect(payload.truncated == false)
    #expect(payload.lineCount == 2)
    #expect(payload.text == "c\nd")
  }

  @Test func lastUsesScrollbackWhenViewportInsufficient() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "c\nd",
          screenText: "a\nb\nc\nd"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 3))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.source == .scrollback)
    #expect(payload.truncated == false)
    #expect(payload.lineCount == 3)
    #expect(payload.text == "b\nc\nd")
  }

  @Test func lastMarksTruncatedWhenScreenInsufficient() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "three\nfour",
          screenText: "one\ntwo\nthree\nfour"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 10))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.source == .scrollback)
    #expect(payload.truncated == true)
    #expect(payload.lineCount == 4)
    #expect(payload.text == "one\ntwo\nthree\nfour")
  }

  @Test func lastFallsBackToViewportWhenScreenCaptureUnavailable() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "three\nfour",
          screenText: nil
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 10))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.source == .mixed)
    #expect(payload.truncated == true)
    #expect(payload.lineCount == 2)
    #expect(payload.text == "three\nfour")
  }

  @Test func lastPrefersViewportWhenScreenHasFewerLines() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "b\nc\nd",
          screenText: "c\nd"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 5))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.source == .mixed)
    #expect(payload.truncated == true)
    #expect(payload.lineCount == 3)
    #expect(payload.text == "b\nc\nd")
  }

  @Test func trailingNewlineCountsAsExtraLine() async throws {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in
        ReadCaptureInput(
          viewportText: "done\n",
          screenText: "done\n"
        )
      }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: ReadCommandPayload.self))
    #expect(payload.lineCount == 2)
    #expect(payload.text == "done\n")
  }

  @Test func targetNotFoundMapsToContractCode() async {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .failure(.notFound("Pane missing")) },
      captureProvider: { _ in nil }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotFound)
  }

  @Test func targetNotUniqueMapsToContractCode() async {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .failure(.notUnique("Ambiguous worktree")) },
      captureProvider: { _ in nil }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope(last: 3))

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotUnique)
  }

  @Test func captureFailureReturnsReadFailed() async {
    let handler = ReadCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      captureProvider: { _ in nil }
    )

    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.readFailed)
  }
}
