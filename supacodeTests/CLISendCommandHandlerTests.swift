import Foundation
import Testing

@testable import supacode

@MainActor
struct CLISendCommandHandlerTests {

  // MARK: - Helpers

  private static let testPaneID = UUID(uuidString: "6E1A2A10-D99F-4E3F-920C-D93AA3C05764")!
  private static let testTabID = UUID(uuidString: "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0")!

  private static func makeTarget() -> SendResolvedTarget {
    SendResolvedTarget(
      worktreeID: "Prowl:/Users/onevcat/Projects/Prowl",
      worktreeName: "Prowl",
      worktreePath: "/Users/onevcat/Projects/Prowl",
      worktreeRootPath: "/Users/onevcat/Projects/Prowl",
      worktreeKind: .git,
      tabID: testTabID,
      tabTitle: "Prowl 1",
      tabSelected: true,
      paneID: testPaneID,
      paneTitle: "zsh",
      paneCWD: "/Users/onevcat/Projects/Prowl",
      paneFocused: true
    )
  }

  private static func makeHandler(
    resolveResult: Result<SendResolvedTarget, TargetResolverError> = .success(makeTarget()),
    waiterResult: (exitCode: Int?, durationMs: Int)? = nil,
    waiterDelay: Duration? = nil,
    textDelivery: (@MainActor (SendResolvedTarget, String, Bool) -> Void)? = nil
  ) -> SendCommandHandler {
    SendCommandHandler(
      resolveProvider: { _ in resolveResult },
      textDelivery: textDelivery ?? { _, _, _ in },
      waiterProvider: { _, _ in
        guard let waiterResult else { return nil }
        return AsyncStream { continuation in
          if let delay = waiterDelay {
            Task {
              try? await Task.sleep(for: delay)
              continuation.yield(waiterResult)
              continuation.finish()
            }
          } else {
            continuation.yield(waiterResult)
            continuation.finish()
          }
        }
      }
    )
  }

  private static func makeEnvelope(
    text: String = "echo hello",
    trailingEnter: Bool = true,
    source: InputSource = .argv,
    wait: Bool = true,
    timeoutSeconds: Int? = nil
  ) -> CommandEnvelope {
    CommandEnvelope(
      output: .json,
      command: .send(
        SendInput(
          selector: .none,
          text: text,
          trailingEnter: trailingEnter,
          source: source,
          wait: wait,
          timeoutSeconds: timeoutSeconds
        ))
    )
  }

  // MARK: - Tests

  @Test func successfulSendWithWait() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 1234)
    )
    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    #expect(response.command == "send")
    #expect(response.schemaVersion == "prowl.cli.send.v1")

    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.target.worktree.id == "Prowl:/Users/onevcat/Projects/Prowl")
    #expect(payload.target.worktree.kind == "git")
    #expect(payload.target.tab.id == Self.testTabID.uuidString)
    #expect(payload.target.tab.selected == true)
    #expect(payload.target.pane.id == Self.testPaneID.uuidString)
    #expect(payload.target.pane.focused == true)
    #expect(payload.input.source == "argv")
    #expect(payload.input.characters == 10)
    #expect(payload.input.bytes == 10)
    #expect(payload.input.trailingEnterSent == true)
    #expect(payload.createdTab == false)
    #expect(payload.wait?.exitCode == 0)
    #expect(payload.wait?.durationMs == 1234)
  }

  @Test func noWaitReturnsNullWait() async throws {
    let handler = Self.makeHandler()
    let response = await handler.handle(envelope: Self.makeEnvelope(wait: false))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.wait == nil)
  }

  @Test func timeoutReturnsWaitTimeoutError() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 5000),
      waiterDelay: .seconds(10)
    )
    let response = await handler.handle(
      envelope: Self.makeEnvelope(timeoutSeconds: 1)
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.waitTimeout)
  }

  @Test func sourceFieldReflectsStdin() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 100)
    )
    let response = await handler.handle(
      envelope: Self.makeEnvelope(source: .stdin)
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.input.source == "stdin")
  }

  @Test func multibyteCounts() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 50)
    )
    // "café" = 4 unicode scalars, 5 UTF-8 bytes (é = 2 bytes)
    let response = await handler.handle(
      envelope: Self.makeEnvelope(text: "café")
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.input.characters == 4)
    #expect(payload.input.bytes == 5)
  }

  @Test func emojiCounts() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 50)
    )
    // "hi👋" = 3 unicode scalars (hi + wave), 6 UTF-8 bytes (h=1, i=1, 👋=4)
    let response = await handler.handle(
      envelope: Self.makeEnvelope(text: "hi👋")
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.input.characters == 3)
    #expect(payload.input.bytes == 6)
  }

  @Test func trailingEnterSentMatchesInput() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 50)
    )
    let response = await handler.handle(
      envelope: Self.makeEnvelope(trailingEnter: false)
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.input.trailingEnterSent == false)
  }

  @Test func targetNotFoundError() async throws {
    let handler = Self.makeHandler(
      resolveResult: .failure(.notFound("Worktree 'missing' not found."))
    )
    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotFound)
  }

  @Test func targetNotUniqueError() async throws {
    let handler = Self.makeHandler(
      resolveResult: .failure(.notUnique("Worktree 'Prowl' matches 2 worktrees."))
    )
    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotUnique)
  }

  @Test func waitWithNonZeroExitCode() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: 1, durationMs: 500)
    )
    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.wait?.exitCode == 1)
    #expect(payload.wait?.durationMs == 500)
  }

  @Test func waitWithNullExitCode() async throws {
    let handler = Self.makeHandler(
      waiterResult: (exitCode: nil, durationMs: 200)
    )
    let response = await handler.handle(envelope: Self.makeEnvelope())

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: SendCommandPayload.self))
    #expect(payload.wait?.exitCode == nil)
  }

  @Test func textDeliveryReceivesCorrectArguments() async throws {
    var deliveredText: String?
    var deliveredTrailingEnter: Bool?

    let handler = Self.makeHandler(
      waiterResult: (exitCode: 0, durationMs: 10),
      textDelivery: { _, text, trailingEnter in
        deliveredText = text
        deliveredTrailingEnter = trailingEnter
      }
    )
    _ = await handler.handle(envelope: Self.makeEnvelope(text: "git status", trailingEnter: false))

    #expect(deliveredText == "git status")
    #expect(deliveredTrailingEnter == false)
  }
}
