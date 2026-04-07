import ComposableArchitecture
import SwiftUI

struct SidebarFooterView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.surfaceBottomChromeBackgroundOpacity) private var surfaceBottomChromeBackgroundOpacity
  @Environment(\.openURL) private var openURL
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    HStack {
      Button {
        store.send(.setOpenPanelPresented(true))
      } label: {
        HStack(spacing: 6) {
          Label("Add Repository", systemImage: "folder.badge.plus")
            .font(.callout)
          if commandKeyObserver.isPressed,
            let shortcut = shortcutDisplay(for: AppShortcuts.CommandID.openRepository)
          {
            ShortcutHintView(text: shortcut, color: .secondary)
          }
        }
      }
      .help(
        AppShortcuts.helpText(
          title: "Add Repository",
          commandID: AppShortcuts.CommandID.openRepository,
          in: resolvedKeybindings
        ))
      Spacer()
      Menu {
        Button("Submit GitHub issue", systemImage: "exclamationmark.bubble") {
          if let url = URL(string: "https://github.com/onevcat/supacode/issues/new") {
            openURL(url)
          }
        }
        .help("Submit GitHub issue")
      } label: {
        Label("Help", systemImage: "questionmark.circle")
          .labelStyle(.iconOnly)
      }
      .menuIndicator(.hidden)
      .help("Help")
      Button {
        store.send(.refreshWorktrees)
      } label: {
        Image(systemName: "arrow.clockwise")
          .symbolEffect(.rotate, options: .repeating, isActive: store.state.isRefreshingWorktrees)
          .accessibilityLabel("Refresh Worktrees")
      }
      .help(
        AppShortcuts.helpText(
          title: "Refresh Worktrees",
          commandID: AppShortcuts.CommandID.refreshWorktrees,
          in: resolvedKeybindings
        )
      )
      .disabled(store.state.repositoryRoots.isEmpty && !store.state.isRefreshingWorktrees)
      Button {
        store.send(.selectArchivedWorktrees)
      } label: {
        Image(systemName: "archivebox")
          .accessibilityLabel("Archived Worktrees")
      }
      .help(
        AppShortcuts.helpText(
          title: "Archived Worktrees",
          commandID: AppShortcuts.CommandID.archivedWorktrees,
          in: resolvedKeybindings
        ))
      Button("Settings", systemImage: "gearshape") {
        SettingsWindowManager.shared.show()
      }
      .labelStyle(.iconOnly)
      .help(
        AppShortcuts.helpText(
          title: "Settings",
          commandID: AppShortcuts.CommandID.openSettings,
          in: resolvedKeybindings
        ))
    }
    .buttonStyle(.plain)
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      if surfaceBottomChromeBackgroundOpacity < 1 {
        Rectangle().fill(.regularMaterial)
      } else {
        Color(nsColor: .windowBackgroundColor)
      }
    }
    .overlay(alignment: .top) {
      Divider()
    }
  }

  private func shortcutDisplay(for commandID: String) -> String? {
    AppShortcuts.display(for: commandID, in: resolvedKeybindings)
  }
}
