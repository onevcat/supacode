import AppKit
import Carbon
import Testing

@testable import supacode

struct CLIKeyTokenExpansionTests {
  @Test func normalizesExpandedModifierCombos() {
    #expect(KeyTokens.normalize("cmd-c") == "cmd-c")
    #expect(KeyTokens.normalize("command-shift-k") == "cmd-shift-k")
    #expect(KeyTokens.normalize("alt-enter") == "opt-enter")
    #expect(KeyTokens.normalize("ctrl-z") == "ctrl-z")
  }

  @Test func normalizesPrintableAliasesToCanonicalAnsiTokens() {
    #expect(KeyTokens.normalize("[") == "left-bracket")
    #expect(KeyTokens.normalize("]") == "right-bracket")
    #expect(KeyTokens.normalize(",") == "comma")
    #expect(KeyTokens.normalize("'") == "quote")
  }

  @Test func normalizesAdditionalNamedKeys() {
    #expect(KeyTokens.normalize("deleteforward") == "delete-forward")
    #expect(KeyTokens.normalize("forward-delete") == "delete-forward")
    #expect(KeyTokens.normalize("ins") == "insert")
    #expect(KeyTokens.normalize("f12") == "f12")
  }

  @Test func rejectsUnsupportedShiftedSymbolLiterals() {
    #expect(KeyTokens.normalize("!") == nil)
    #expect(KeyTokens.normalize("@") == nil)
    #expect(CLIKeySpec.from(token: "!") == nil)
    #expect(CLIKeySpec.from(token: "@") == nil)
  }

  @Test func expandedCategoriesAreReported() {
    #expect(KeyTokens.category(for: "cmd-c") == .shortcut)
    #expect(KeyTokens.category(for: "ctrl-z") == .control)
    #expect(KeyTokens.category(for: "f12") == .function)
  }

  @Test func cliKeySpecBuildsCommandShortcutEvent() throws {
    let spec = try #require(CLIKeySpec.from(token: "cmd-c"))

    #expect(spec.keyCode == UInt16(kVK_ANSI_C))
    #expect(spec.modifiers == [.command])
    #expect(spec.characters == "c")
    #expect(spec.charactersIgnoringModifiers == "c")
  }

  @Test func cliKeySpecBuildsShiftedShortcutEvent() throws {
    let spec = try #require(CLIKeySpec.from(token: "cmd-shift-k"))

    #expect(spec.keyCode == UInt16(kVK_ANSI_K))
    #expect(spec.modifiers == [.command, .shift])
    #expect(spec.characters == "K")
    #expect(spec.charactersIgnoringModifiers == "k")
  }

  @Test func cliKeySpecBuildsShiftedAnsiPunctuationEvent() throws {
    let spec = try #require(CLIKeySpec.from(token: "shift-left-bracket"))

    #expect(spec.keyCode == UInt16(kVK_ANSI_LeftBracket))
    #expect(spec.modifiers == [.shift])
    #expect(spec.characters == "{")
    #expect(spec.charactersIgnoringModifiers == "[")
  }

  @Test func cliKeySpecBuildsFunctionAndForwardDeleteEvents() throws {
    let f12 = try #require(CLIKeySpec.from(token: "f12"))
    #expect(f12.keyCode == UInt16(kVK_F12))
    #expect(f12.modifiers == [.function])
    #expect(f12.characters == String(UnicodeScalar(NSF12FunctionKey)!))

    let deleteForward = try #require(CLIKeySpec.from(token: "delete-forward"))
    #expect(deleteForward.keyCode == UInt16(kVK_ForwardDelete))
    #expect(deleteForward.modifiers == [.function])
    #expect(deleteForward.characters == String(UnicodeScalar(NSDeleteFunctionKey)!))
  }
}
