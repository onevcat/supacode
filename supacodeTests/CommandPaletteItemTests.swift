import CustomDump
import Testing

@testable import supacode

struct CommandPaletteItemTests {
  @Test func appShortcutLabelUsesResolvedKeybindings() {
    let overrides = KeybindingUserOverrideStore(
      overrides: [
        AppShortcuts.ID.openSettings: KeybindingUserOverride(
          binding: Keybinding(key: ";", modifiers: .init(command: true))
        )
      ]
    )
    let resolved = KeybindingResolver.resolve(
      schema: .appResolverSchema(),
      userOverrides: overrides
    )
    let item = CommandPaletteItem(
      id: "settings",
      title: "Open Settings",
      subtitle: nil,
      kind: .openSettings
    )

    expectNoDifference(item.appShortcutLabel(in: resolved), "⌘;")
    expectNoDifference(item.appShortcutSymbols(in: resolved)?.joined(), "⌘;")
  }
}
