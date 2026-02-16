import Testing

@testable import supacode

struct OpenWorktreeActionTests {
  @Test func menuOrderIncludesExpectedWorkspaceActions() {
    let settingsIDs = OpenWorktreeAction.menuOrder.map(\.settingsID)

    #expect(settingsIDs.contains("antigravity"))
    #expect(settingsIDs.contains("vscode-insiders"))
    #expect(settingsIDs.contains("warp"))
    #expect(settingsIDs.contains("webstorm"))
    #expect(settingsIDs.contains("pycharm"))
  }

  @Test func jetBrainsIDEsHaveCorrectBundleIdentifiers() {
    #expect(OpenWorktreeAction.webstorm.bundleIdentifier == "com.jetbrains.WebStorm")
    #expect(OpenWorktreeAction.pycharm.bundleIdentifier == "com.jetbrains.pycharm")
  }

  @Test func jetBrainsIDEsAreInEditorPriority() {
    let editors = OpenWorktreeAction.editorPriority
    #expect(editors.contains(.webstorm))
    #expect(editors.contains(.pycharm))
  }
}
