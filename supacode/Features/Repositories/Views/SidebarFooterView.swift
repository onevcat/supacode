import ComposableArchitecture
import SwiftUI

struct SidebarFooterView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.surfaceBottomChromeBackgroundOpacity) private var surfaceBottomChromeBackgroundOpacity
  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack {
      Menu {
        Button {
          store.send(.setOpenPanelPresented(true))
        } label: {
          Label("Add Repository", systemImage: "folder.badge.plus")
        }
        .keyboardShortcut(AppShortcuts.openRepository.keyboardShortcut)
        .help("Add Repository (\(AppShortcuts.openRepository.display))")

        Button {
          store.send(.addRemoteRepositoryButtonTapped)
        } label: {
          Label("Add Remote Repository", systemImage: "server.rack")
        }
        .help("Connect Remote Repository")
        } label: {
          Label("Add", systemImage: "plus")
            .font(.callout)
        }
      .help("Add Repository or Remote Repository")
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
      .help("Refresh Worktrees (\(AppShortcuts.refreshWorktrees.display))")
      .disabled(store.state.repositoryRoots.isEmpty && !store.state.isRefreshingWorktrees)
      Button {
        store.send(.selectArchivedWorktrees)
      } label: {
        Image(systemName: "archivebox")
          .accessibilityLabel("Archived Worktrees")
      }
      .help("Archived Worktrees (\(AppShortcuts.archivedWorktrees.display))")
      Button("Settings", systemImage: "gearshape") {
        SettingsWindowManager.shared.show()
      }
      .labelStyle(.iconOnly)
      .help("Settings (\(AppShortcuts.openSettings.display))")
    }
    .buttonStyle(.plain)
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor).opacity(surfaceBottomChromeBackgroundOpacity))
    .overlay(alignment: .top) {
      Divider()
    }
  }
}
