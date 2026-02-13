import SwiftUI

struct TerminalTabContentStack<Content: View>: View {
  let selectedTabId: TerminalTabID
  let content: (TerminalTabID) -> Content

  init(
    selectedTabId: TerminalTabID,
    @ViewBuilder content: @escaping (TerminalTabID) -> Content
  ) {
    self.selectedTabId = selectedTabId
    self.content = content
  }

  var body: some View {
    content(selectedTabId)
      .accessibilityHidden(false)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
