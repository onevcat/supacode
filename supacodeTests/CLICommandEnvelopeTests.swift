// supacodeTests/CLICommandEnvelopeTests.swift
// Contract tests for CommandEnvelope, CommandResponse, and shared types.

import Foundation
import Testing

@testable import supacode

struct CLICommandEnvelopeTests {

  // MARK: - CommandEnvelope round-trip

  @Test func envelopeOpenRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/Users/test/project"))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)

    #expect(decoded.output == .json)
    if case .open(let input) = decoded.command {
      #expect(input.path == "/Users/test/project")
    } else {
      Issue.record("Expected .open command")
    }
  }

  @Test func envelopeOpenNilPathRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .text,
      command: .open(OpenInput(path: nil))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)

    if case .open(let input) = decoded.command {
      #expect(input.path == nil)
    } else {
      Issue.record("Expected .open command")
    }
  }

  @Test func envelopeListRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .text,
      command: .list(ListInput())
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    #expect(decoded.output == .text)
    if case .list = decoded.command {
      // expected
    } else {
      Issue.record("Expected .list command")
    }
  }

  @Test func envelopeSendWithSelectorRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .json,
      command: .send(
        SendInput(
          selector: .pane("abc-123"),
          text: "hello world",
          trailingEnter: false
        ))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    if case .send(let input) = decoded.command {
      #expect(input.text == "hello world")
      #expect(input.trailingEnter == false)
      #expect(input.selector == .pane("abc-123"))
    } else {
      Issue.record("Expected .send command")
    }
  }

  @Test func envelopeKeyWithRepeatRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .text,
      command: .key(
        KeyInput(
          selector: .tab("tab-1"),
          rawToken: "enter",
          token: "enter",
          repeatCount: 5
        ))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    if case .key(let input) = decoded.command {
      #expect(input.token == "enter")
      #expect(input.repeatCount == 5)
      #expect(input.selector == .tab("tab-1"))
    } else {
      Issue.record("Expected .key command")
    }
  }

  @Test func envelopeReadWithLastRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .json,
      command: .read(ReadInput(selector: .worktree("wt-main"), last: 50))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    if case .read(let input) = decoded.command {
      #expect(input.last == 50)
      #expect(input.selector == .worktree("wt-main"))
    } else {
      Issue.record("Expected .read command")
    }
  }

  @Test func envelopeFocusNoSelectorRoundTrips() throws {
    let envelope = CommandEnvelope(
      output: .text,
      command: .focus(FocusInput(selector: .none))
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    if case .focus(let input) = decoded.command {
      #expect(input.selector == .none)
    } else {
      Issue.record("Expected .focus command")
    }
  }

  // MARK: - Command name

  @Test func commandNameReturnsCorrectStrings() {
    let commands: [(Command, String)] = [
      (.open(OpenInput(path: nil)), "open"),
      (.list(ListInput()), "list"),
      (.focus(FocusInput()), "focus"),
      (.send(SendInput(text: "x")), "send"),
      (.key(KeyInput(rawToken: "tab", token: "tab")), "key"),
      (.read(ReadInput()), "read"),
    ]
    for (command, expected) in commands {
      #expect(command.name == expected)
    }
  }

  // MARK: - Encoding produces valid JSON

  @Test func allCommandsEncodeToValidJSON() throws {
    let commands: [Command] = [
      .open(OpenInput(path: "/tmp")),
      .list(ListInput()),
      .focus(FocusInput()),
      .send(SendInput(text: "test")),
      .key(KeyInput(rawToken: "enter", token: "enter")),
      .read(ReadInput()),
    ]
    for cmd in commands {
      let envelope = CommandEnvelope(output: .json, command: cmd)
      let data = try JSONEncoder().encode(envelope)
      let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(json["output"] as? String == "json")
      #expect(json["command"] != nil)
    }
  }
}
