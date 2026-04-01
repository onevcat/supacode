import ComposableArchitecture
import SwiftUI

struct SidebarFooterView: View {
  let store: StoreOf<RepositoriesFeature>
  let remoteGroupsStore: StoreOf<RemoteGroupsFeature>
  @Environment(\.surfaceBottomChromeBackgroundOpacity) private var surfaceBottomChromeBackgroundOpacity
  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack {
      Button {
        remoteGroupsStore.send(.setAddPromptPresented(true))
      } label: {
        Image(systemName: "link.badge.plus")
          .accessibilityLabel("Add Remote Endpoint")
      }
      .help("Add Remote Endpoint")
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
