import ComposableArchitecture
import SwiftUI

struct CanvasSidebarButton: View {
  let store: StoreOf<RepositoriesFeature>
  let isSelected: Bool
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    Button {
      store.send(.selectCanvas)
    } label: {
      HStack(spacing: 6) {
        Label("Canvas", systemImage: "square.grid.2x2")
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
        if commandKeyObserver.isPressed {
          ShortcutHintView(text: AppShortcuts.toggleCanvas.display, color: .secondary)
        }
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
    .help("Canvas (\(AppShortcuts.toggleCanvas.display))")
  }
}
