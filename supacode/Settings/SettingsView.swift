import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("Agents", systemImage: "terminal") {
        CodingAgentSettingsView()
      }
      Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
        ChatSettingsView()
      }
      Tab("Appearance", systemImage: "paintpalette") {
        AppearanceSettingsView()
      }
      Tab("Updates", systemImage: "arrow.down.circle") {
        UpdatesSettingsView()
      }
    }
    .scenePadding()
    .frame(minWidth: 560, minHeight: 420)
    .background(WindowLevelSetter(level: .floating))
  }
}
