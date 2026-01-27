import ComposableArchitecture
import SwiftUI

private extension View {
  @ViewBuilder
  func removingSidebarToggle() -> some View {
    if #available(macOS 14.0, *) {
      toolbar(removing: .sidebarToggle)
    } else {
      self
    }
  }
}

struct SettingsView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var selection: SettingsSection? = .agents

  var body: some View {
    let settingsStore = store.scope(state: \.settings, action: \.settings)
    let updatesStore = store.scope(state: \.updates, action: \.updates)
    let repositories = store.repositories.repositories

    NavigationSplitView(columnVisibility: .constant(.all)) {
      VStack(spacing: 0) {
        List(selection: $selection) {
          Label("Agents", systemImage: "terminal")
            .tag(SettingsSection.agents)
          Label("Chat", systemImage: "bubble.left.and.bubble.right")
            .tag(SettingsSection.chat)
          Label("Appearance", systemImage: "paintpalette")
            .tag(SettingsSection.appearance)
          Label("Notifications", systemImage: "bell")
            .tag(SettingsSection.notifications)
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
      case .agents:
        SettingsDetailView {
          CodingAgentSettingsView()
            .navigationTitle("Agents")
            .navigationSubtitle("Coding agents and tools")
        }
      case .chat:
        SettingsDetailView {
          ChatSettingsView()
            .navigationTitle("Chat")
            .navigationSubtitle("Chat experience and defaults")
        }
      case .appearance:
        SettingsDetailView {
          AppearanceSettingsView(store: settingsStore)
            .navigationTitle("Appearance")
            .navigationSubtitle("Theme and visuals")
        }
      case .notifications:
        SettingsDetailView {
          NotificationsSettingsView(store: settingsStore)
            .navigationTitle("Notifications")
            .navigationSubtitle("In-app alerts and delivery")
        }
      case .updates:
        SettingsDetailView {
          UpdatesSettingsView(settingsStore: settingsStore, updatesStore: updatesStore)
            .navigationTitle("Updates")
            .navigationSubtitle("Update preferences")
        }
      case .github:
        SettingsDetailView {
          GithubSettingsView()
            .navigationTitle("GitHub")
            .navigationSubtitle("GitHub CLI integration")
        }
      case .repository(let repositoryID):
        if let repository = repositories.first(where: { $0.id == repositoryID }) {
          SettingsDetailView {
            RepositorySettingsContainerView(repository: repository)
              .id(repository.id)
            .navigationTitle(repository.name)
            .navigationSubtitle(repository.rootURL.path(percentEncoded: false))
          }
        } else {
          SettingsDetailView {
            Text("Repository not found.")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .navigationTitle("Repositories")
          }
        }
      case .none:
        SettingsDetailView {
          CodingAgentSettingsView()
            .navigationTitle("Agents")
            .navigationSubtitle("Coding agents and tools")
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
    .onChange(of: repositories) { _, updatedRepositories in
      guard case .repository(let repositoryID) = selection else { return }
      if !updatedRepositories.contains(where: { $0.id == repositoryID }) {
        selection = .agents
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openRepositorySettings)) { notification in
      if let repositoryID = notification.object as? Repository.ID {
        selection = .repository(repositoryID)
      }
    }
  }
}
