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
      _ = store.send(.openRepositorySettings(repository.id))
    }
    Section {
      WorktreeRowsView(
        repository: repository,
        isExpanded: isExpanded,
        store: store,
        terminalManager: terminalManager
      )
    } header: {
      let toggleExpanded = {
        if expandedRepoIDs.contains(repository.id) {
          expandedRepoIDs.remove(repository.id)
        } else {
          expandedRepoIDs.insert(repository.id)
        }
      }
      HStack {
        RepoHeaderRow(
          name: repository.name,
          initials: repository.initials,
          isExpanded: isExpanded,
          isRemoving: isRemovingRepository
        )
        Spacer()
        if isRemovingRepository {
          ProgressView()
            .controlSize(.small)
        }
        Menu {
          Button("Repo Settings") {
            openRepoSettings()
          }
          .help("Repo Settings ")
          Button("Remove Repository") {
            store.send(.requestRemoveRepository(repository.id))
          }
          .help("Remove repository ")
          .disabled(isRemovingRepository)
        } label: {
          Label("Repository options", systemImage: "ellipsis")
            .labelStyle(.iconOnly)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Repository options ")
        .disabled(isRemovingRepository)
        Button {
          store.send(.createRandomWorktreeInRepository(repository.id))
        } label: {
          Label("New Worktree", systemImage: "plus")
            .labelStyle(.iconOnly)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.trailing, 6)
        .help("New Worktree (\(AppShortcuts.newWorktree.display))")
        .disabled(isRemovingRepository)
      }
      .contentShape(Rectangle())
      .onTapGesture {
        toggleExpanded()
      }
      .accessibilityAddTraits(.isButton)
      .disabled(isRemovingRepository)
      .contextMenu {
        Button("Repo Settings") {
          openRepoSettings()
        }
        .help("Repo Settings ")
        Button("Remove Repository") {
          store.send(.requestRemoveRepository(repository.id))
        }
        .help("Remove repository ")
        .disabled(isRemovingRepository)
      }
      .padding()
      .padding(.bottom, isExpanded ? 6 : 0)
    }
  }
}
