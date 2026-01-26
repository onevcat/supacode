import ComposableArchitecture
import SwiftUI

struct RepositorySectionView: View {
  let repository: Repository
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    let state = store.state
    let isExpanded = expandedRepoIDs.contains(repository.id)
    let isRemovingRepository = state.isRemovingRepository(repository)
    let openRepoSettings = {
      _ = Task { @MainActor in
        SettingsWindowManager.shared.show()
        await Task.yield()
        NotificationCenter.default.post(name: .openRepositorySettings, object: repository.id)
      }
    }
    Section {
      WorktreeRowsView(
        repository: repository,
        isExpanded: isExpanded,
        store: store,
        terminalManager: terminalManager
      )
    } header: {
      HStack {
        Button {
          if expandedRepoIDs.contains(repository.id) {
            expandedRepoIDs.remove(repository.id)
          } else {
            expandedRepoIDs.insert(repository.id)
          }
        } label: {
          HStack {
            RepoHeaderRow(
              name: repository.name,
              initials: repository.initials,
              isExpanded: isExpanded,
              isRemoving: isRemovingRepository
            )
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRemovingRepository)
        .contextMenu {
          Button("Repo Settings") {
            openRepoSettings()
          }
          .help("Repo Settings (no shortcut)")
          Button("Remove Repository") {
            store.send(.requestRemoveRepository(repository.id))
          }
          .help("Remove repository (no shortcut)")
          .disabled(isRemovingRepository)
        }
        if isRemovingRepository {
          ProgressView()
            .controlSize(.small)
        }
        Menu {
          Button("Repo Settings") {
            openRepoSettings()
          }
          .help("Repo Settings (no shortcut)")
          Button("Remove Repository") {
            store.send(.requestRemoveRepository(repository.id))
          }
          .help("Remove repository (no shortcut)")
          .disabled(isRemovingRepository)
        } label: {
          Label("Repository options", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Repository options (no shortcut)")
        .disabled(isRemovingRepository)
        Button("New Worktree", systemImage: "plus") {
          store.send(.createRandomWorktreeInRepository(repository.id))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.trailing, 6)
        .help("New Worktree (\(AppShortcuts.newWorktree.display))")
        .disabled(isRemovingRepository)
      }
      .padding()
      .padding(.bottom, isExpanded ? 6 : 0)
    }
  }
}
