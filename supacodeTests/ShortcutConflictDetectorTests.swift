import Testing

@testable import supacode

struct ShortcutConflictDetectorTests {
  @Test func localOnlyPolicyWarnsWhenBindingConflictsWithAppAction() {
    let globalID = "command.global"
    let localID = "command.local"
    let conflictBinding = binding("r", modifiers: .init(command: true, shift: true))

    let schema = testSchema([
      testCommand(
        id: globalID,
        title: "Refresh Worktrees",
        conflictPolicy: .warnAndPreferUserOverride,
        defaultBinding: conflictBinding
      ),
      testCommand(
        id: localID,
        title: "Rename Branch",
        conflictPolicy: .localOnly,
        defaultBinding: binding("m", modifiers: .init(command: true, shift: true))
      ),
    ])

    let conflictID = ShortcutConflictDetector.firstConflictCommandID(
      commandID: localID,
      binding: conflictBinding,
      policy: .localOnly,
      schema: schema,
      userOverrides: .empty
    )

    #expect(conflictID == globalID)
  }

  @Test func disallowPolicyDoesNotWarn() {
    let schema = testSchema([
      testCommand(
        id: "command.fixed",
        title: "Fixed",
        conflictPolicy: .disallowUserOverride,
        defaultBinding: binding("a", modifiers: .init(command: true))
      ),
      testCommand(
        id: "command.other",
        title: "Other",
        conflictPolicy: .warnAndPreferUserOverride,
        defaultBinding: binding("a", modifiers: .init(command: true))
      ),
    ])

    let conflictID = ShortcutConflictDetector.firstConflictCommandID(
      commandID: "command.fixed",
      binding: binding("a", modifiers: .init(command: true)),
      policy: .disallowUserOverride,
      schema: schema,
      userOverrides: .empty
    )

    #expect(conflictID == nil)
  }

  @Test func returnsNilWhenNoConflict() {
    let schema = testSchema([
      testCommand(
        id: "command.one",
        title: "One",
        conflictPolicy: .warnAndPreferUserOverride,
        defaultBinding: binding("a", modifiers: .init(command: true))
      ),
      testCommand(
        id: "command.two",
        title: "Two",
        conflictPolicy: .localOnly,
        defaultBinding: binding("b", modifiers: .init(command: true))
      ),
    ])

    let conflictID = ShortcutConflictDetector.firstConflictCommandID(
      commandID: "command.two",
      binding: binding("c", modifiers: .init(command: true)),
      policy: .localOnly,
      schema: schema,
      userOverrides: .empty
    )

    #expect(conflictID == nil)
  }

  private func testSchema(_ commands: [KeybindingCommandSchema]) -> KeybindingSchemaDocument {
    KeybindingSchemaDocument(
      version: KeybindingSchemaDocument.currentVersion,
      commands: commands
    )
  }

  private func testCommand(
    id: String,
    title: String,
    conflictPolicy: KeybindingConflictPolicy,
    defaultBinding: Keybinding
  ) -> KeybindingCommandSchema {
    KeybindingCommandSchema(
      id: id,
      title: title,
      scope: .configurableAppAction,
      platform: .macOS,
      allowUserOverride: true,
      conflictPolicy: conflictPolicy,
      defaultBinding: defaultBinding
    )
  }

  private func binding(
    _ key: String,
    modifiers: KeybindingModifiers
  ) -> Keybinding {
    Keybinding(
      key: key,
      modifiers: modifiers
    )
  }
}
