import ComposableArchitecture
import SwiftUI

extension View {
  @ViewBuilder
  fileprivate func removingSidebarToggle() -> some View {
    if #available(macOS 14.0, *) {
      toolbar(removing: .sidebarToggle)
    } else {
      self
    }
  }
}

struct SettingsView: View {
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    let settingsStore = store.scope(state: \.settings, action: \.settings)
    let updatesStore = store.scope(state: \.updates, action: \.updates)
    let repositories = store.repositories.repositories
    let selection = store.settings.selection
    let selectionBinding = Binding<SettingsSection?>(
      get: { store.settings.selection },
      set: { selection in
        store.send(.settings(.setSelection(selection ?? .general)))
      }
    )

    NavigationSplitView(columnVisibility: .constant(.all)) {
      VStack(spacing: 0) {
        List(selection: selectionBinding) {
          Label("General", systemImage: "gearshape")
            .tag(SettingsSection.general)
          Label("Notifications", systemImage: "bell")
            .tag(SettingsSection.notifications)
          Label("Worktree", systemImage: "archivebox")
            .tag(SettingsSection.worktree)
          Label("Updates", systemImage: "arrow.down.circle")
            .tag(SettingsSection.updates)
          Label("GitHub", systemImage: "arrow.triangle.branch")
            .tag(SettingsSection.github)

          Section("Repositories") {
            ForEach(repositories) { repository in
              Text(repository.name)
                .tag(SettingsSection.repository(repository.id))
            }
          }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(220)
        .removingSidebarToggle()
      }
    } detail: {
      switch selection {
      case .general:
        SettingsDetailView {
          AppearanceSettingsView(store: settingsStore)
            .navigationTitle("General")
            .navigationSubtitle("Appearance and preferences")
        }
      case .notifications:
        SettingsDetailView {
          NotificationsSettingsView(store: settingsStore)
            .navigationTitle("Notifications")
            .navigationSubtitle("In-app alerts and delivery")
        }
      case .worktree:
        SettingsDetailView {
          WorktreeSettingsView(store: settingsStore)
            .navigationTitle("Worktree")
            .navigationSubtitle("Archive behavior")
        }
      case .updates:
        SettingsDetailView {
          UpdatesSettingsView(settingsStore: settingsStore, updatesStore: updatesStore)
            .navigationTitle("Updates")
            .navigationSubtitle("Update preferences")
        }
      case .github:
        SettingsDetailView {
          GithubSettingsView(store: settingsStore)
            .navigationTitle("GitHub")
            .navigationSubtitle("GitHub CLI integration")
        }
      case .repository(let repositoryID):
        if let repository = repositories[id: repositoryID] {
          SettingsDetailView {
            IfLetStore(
              settingsStore.scope(state: \.repositorySettings, action: \.repositorySettings)
            ) { repositorySettingsStore in
              RepositorySettingsView(store: repositorySettingsStore)
                .id(repository.id)
                .navigationTitle(repository.name)
                .navigationSubtitle(repository.rootURL.path(percentEncoded: false))
            }
          }
        } else {
          SettingsDetailView {
            Text("Repository not found.")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .navigationTitle("Repositories")
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Color.clear
          .frame(width: 1, height: 1)
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 750, minHeight: 500)
    .background(WindowLevelSetter(level: .floating))
    .ignoresSafeArea(.container, edges: .top)
  }
}
