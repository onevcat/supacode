import Testing

@testable import supacode

struct GhosttyUserConfigSnapshotTests {
  @Test func detectsDualTheme() {
    let snapshot = GhosttyUserConfigSnapshot.parse(
      showConfigOutput: """
        theme = light:Catppuccin Latte,dark:Catppuccin Frappe
        background = #1f1f28
        """)

    #expect(snapshot.themeMode == .dual)
  }

  @Test func detectsSingleTheme() {
    let snapshot = GhosttyUserConfigSnapshot.parse(
      showConfigOutput: """
        theme = kanagawabones
        background = #f2f2f2
        """)

    #expect(snapshot.themeMode == .single)
  }

  @Test func detectsUnsetTheme() {
    let snapshot = GhosttyUserConfigSnapshot.parse(
      showConfigOutput: """
        background = #1f1f28
        """)

    #expect(snapshot.themeMode == .none)
  }

  @Test func classifiesBackgroundToneLightDarkUnknown() {
    let dark = GhosttyUserConfigSnapshot.parse(showConfigOutput: "background = #1a1a1a")
    #expect(dark.backgroundTone == .dark)

    let light = GhosttyUserConfigSnapshot.parse(showConfigOutput: "background = #f4f4f4")
    #expect(light.backgroundTone == .light)

    // Popular tinted dark backgrounds should still classify as dark.
    let kanagawa = GhosttyUserConfigSnapshot.parse(showConfigOutput: "background = #1f1f28")
    #expect(kanagawa.backgroundTone == .dark)

    let solarizedDark = GhosttyUserConfigSnapshot.parse(showConfigOutput: "background = #002b36")
    #expect(solarizedDark.backgroundTone == .dark)

    // Mid-luminance colors remain ambiguous and must not trigger a fallback.
    let mid = GhosttyUserConfigSnapshot.parse(showConfigOutput: "background = #808080")
    #expect(mid.backgroundTone == .unknown)
  }
}
