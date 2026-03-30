import CustomDump
import Foundation
import Testing

@testable import supacode

@MainActor
struct KeybindingSchemaTests {
  @Test func schemaEncodeDecodeRoundTripsWithVersion() throws {
    let schema = KeybindingSchemaDocument(
      version: 1,
      commands: [
        KeybindingCommandSchema(
          id: "toggle_left_sidebar",
          title: "Toggle Left Sidebar",
          scope: .configurableAppAction,
          platform: .macOS,
          allowUserOverride: true,
          conflictPolicy: .warnAndPreferUserOverride,
          defaultBinding: Keybinding(
            key: "s",
            modifiers: KeybindingModifiers(command: true, control: true)
          )
        ),
      ]
    )

    let encoded = try JSONEncoder().encode(schema)
    let decoded = try JSONDecoder().decode(KeybindingSchemaDocument.self, from: encoded)

    expectNoDifference(decoded, schema)
    #expect(decoded.version == 1)
  }

  @Test func appDefaultsSchemaIncludesCurrentRegistryAndVersion() {
    let schema = KeybindingSchemaDocument.appDefaultsV1

    #expect(schema.version == KeybindingSchemaDocument.currentVersion)

    let commandIDs = Set(schema.commands.map(\.id))
    #expect(commandIDs.contains("new_worktree"))
    #expect(commandIDs.contains("command_palette"))
    #expect(commandIDs.contains("select_all_canvas_cards"))

    let commandPalette = schema.commands.first(where: { $0.id == "command_palette" })
    #expect(commandPalette?.allowUserOverride == false)
    #expect(commandPalette?.conflictPolicy == .disallowUserOverride)
  }

  @Test func resolverAppliesUserOverrideOverMigratedOverride() {
    let schema = KeybindingSchemaDocument(
      version: 1,
      commands: [
        KeybindingCommandSchema(
          id: "command.alpha",
          title: "Alpha",
          scope: .configurableAppAction,
          platform: .macOS,
          allowUserOverride: true,
          conflictPolicy: .warnAndPreferUserOverride,
          defaultBinding: Keybinding(
            key: "a",
            modifiers: KeybindingModifiers(command: true)
          )
        ),
        KeybindingCommandSchema(
          id: "command.beta",
          title: "Beta",
          scope: .systemFixedAppAction,
          platform: .macOS,
          allowUserOverride: false,
          conflictPolicy: .disallowUserOverride,
          defaultBinding: Keybinding(
            key: "b",
            modifiers: KeybindingModifiers(command: true)
          )
        ),
        KeybindingCommandSchema(
          id: "command.gamma",
          title: "Gamma",
          scope: .configurableAppAction,
          platform: .macOS,
          allowUserOverride: true,
          conflictPolicy: .warnAndPreferUserOverride,
          defaultBinding: Keybinding(
            key: "g",
            modifiers: KeybindingModifiers(command: true)
          )
        ),
      ]
    )

    let migratedOverrides: [String: KeybindingUserOverride] = [
      "command.alpha": KeybindingUserOverride(
        binding: Keybinding(key: "m", modifiers: KeybindingModifiers(command: true))
      ),
    ]

    let userOverrides = KeybindingUserOverrideStore(
      version: 1,
      overrides: [
        "command.alpha": KeybindingUserOverride(
          binding: Keybinding(key: "u", modifiers: KeybindingModifiers(command: true, shift: true))
        ),
        "command.beta": KeybindingUserOverride(
          binding: Keybinding(key: "x", modifiers: KeybindingModifiers(command: true))
        ),
        "command.gamma": KeybindingUserOverride(binding: nil, isEnabled: false),
      ]
    )

    let resolved = KeybindingResolver.resolve(
      schema: schema,
      userOverrides: userOverrides,
      migratedOverrides: migratedOverrides
    )

    #expect(resolved.binding(for: "command.alpha")?.binding?.key == "u")
    #expect(resolved.binding(for: "command.alpha")?.source == .userOverride)

    #expect(resolved.binding(for: "command.beta")?.binding?.key == "b")
    #expect(resolved.binding(for: "command.beta")?.source == .appDefault)

    #expect(resolved.binding(for: "command.gamma")?.binding == nil)
    #expect(resolved.binding(for: "command.gamma")?.source == .userOverride)
  }

  @Test func migrationMigratesLegacyCustomShortcutsAndCollectsUnmappedIssues() throws {
    let fixture = #"""
    {
      "customCommands": [
        {
          "id": "build",
          "title": "Build",
          "systemImage": "hammer",
          "command": "swift build",
          "execution": "shellScript",
          "shortcut": {
            "key": " B ",
            "modifiers": {
              "command": true,
              "shift": true,
              "option": false,
              "control": false
            }
          }
        },
        {
          "id": "deploy",
          "title": "Deploy",
          "systemImage": "rocket",
          "command": "make release",
          "execution": "shellScript",
          "shortcut": {
            "key": "d",
            "modifiers": {
              "command": true,
              "shift": false,
              "option": false,
              "control": false
            }
          }
        },
        {
          "id": "bad-shortcut",
          "title": "Bad",
          "systemImage": "xmark",
          "command": "echo bad",
          "execution": "shellScript",
          "shortcut": {
            "key": "two",
            "modifiers": {
              "command": true,
              "shift": false,
              "option": false,
              "control": false
            }
          }
        },
        {
          "id": "",
          "title": "No ID",
          "systemImage": "questionmark",
          "command": "echo noid",
          "execution": "shellScript",
          "shortcut": {
            "key": "n",
            "modifiers": {
              "command": true,
              "shift": false,
              "option": false,
              "control": false
            }
          }
        },
        {
          "id": "without-shortcut",
          "title": "No Shortcut",
          "systemImage": "ellipsis",
          "command": "echo none",
          "execution": "shellScript",
          "shortcut": null
        }
      ]
    }
    """#

    let legacySettings = try JSONDecoder().decode(
      LegacyCustomCommandShortcutFixture.self,
      from: Data(fixture.utf8)
    )
    let migration = LegacyCustomCommandShortcutMigration.migrate(commands: legacySettings.customCommands)

    #expect(migration.migratedCount == 2)

    let migratedKeys = Set(migration.overrides.keys)
    #expect(migratedKeys == ["custom_command.build", "custom_command.deploy"])

    #expect(migration.overrides["custom_command.build"]?.binding?.key == "b")
    #expect(migration.overrides["custom_command.build"]?.binding?.display == "⌘⇧B")

    expectNoDifference(
      migration.issues.map(\.reason),
      [.invalidShortcut, .missingCommandID]
    )
  }
}

private struct LegacyCustomCommandShortcutFixture: Decodable {
  let customCommands: [UserCustomCommand]
}
