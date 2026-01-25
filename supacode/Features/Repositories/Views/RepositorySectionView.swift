import ComposableArchitecture
import SwiftUI

struct RepositorySectionView: View {
  let repository: Repository
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    let state = store.state
    let isExpanded = expandedRepoIDs.contains(repository.id)
    let isRemovingRepository = state.isRemovingRepository(repository)
    let openRepoSettings = {
      openWindow(id: WindowIdentifiers.repoSettings, value: repository.id)
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
          RepoHeaderRow(
            name: repository.name,
            initials: repository.initials,
            isExpanded: isExpanded,
            isRemoving: isRemovingRepository
          )
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
        Spacer()
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
