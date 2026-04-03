import ComposableArchitecture
import SwiftUI

struct RepositorySectionView: View {
  private static let debugHeaderLayers = false
  let repository: Repository
  let showsTopSeparator: Bool
  let isDragActive: Bool
  let hotkeyRows: [WorktreeRowModel]
  let selectedWorktreeIDs: Set<Worktree.ID>
  @Binding var expandedRepoIDs: Set<Repository.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings
  @State private var isHovering = false

  var body: some View {
    let state = store.state
    let isExpanded = expandedRepoIDs.contains(repository.id)
    let isRemovingRepository = state.isRemovingRepository(repository)
    let isPlainFolderSelected =
      repository.kind == .plain
      && state.selectedRepositoryID == repository.id
    let openRepoSettings = {
      _ = store.send(.repositoryManagement(.openRepositorySettings(repository.id)))
    }
    let toggleExpanded = {
      guard !isRemovingRepository else { return }
      withAnimation(.easeOut(duration: 0.2)) {
        if isExpanded {
          expandedRepoIDs.remove(repository.id)
        } else {
          expandedRepoIDs.insert(repository.id)
        }
      }
    }
    let isDragging = isDragActive

    let header = HStack {
      RepoHeaderRow(
        name: repository.name,
        isRemoving: isRemovingRepository,
        tabCount: Self.openTabCount(
          for: repository,
          terminalManager: terminalManager
        )
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if Self.debugHeaderLayers {
          Rectangle()
            .fill(.green.opacity(0.18))
            .overlay {
              Rectangle()
                .stroke(.green, lineWidth: 1)
            }
        }
      }
      if isRemovingRepository && !isDragging {
        ProgressView()
          .controlSize(.small)
          .background {
            if Self.debugHeaderLayers {
              Rectangle()
                .fill(.yellow.opacity(0.18))
                .overlay {
                  Rectangle()
                    .stroke(.yellow, lineWidth: 1)
                }
            }
          }
      }
      if isHovering && !isDragging {
        Menu {
          Button("Repo Settings") {
            openRepoSettings()
          }
          .help("Repo Settings ")
          Button("Remove Repository") {
            store.send(.repositoryManagement(.requestRemoveRepository(repository.id)))
          }
          .help("Remove repository ")
          .disabled(isRemovingRepository)
        } label: {
          Label("Repository options", systemImage: "ellipsis")
            .labelStyle(.iconOnly)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
              if Self.debugHeaderLayers {
                Rectangle()
                  .fill(.purple.opacity(0.18))
                  .overlay {
                    Rectangle()
                      .stroke(.purple, lineWidth: 1)
                  }
              }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Repository options ")
        .disabled(isRemovingRepository)
        if repository.capabilities.supportsWorktrees {
          Button {
            store.send(.worktreeCreation(.createRandomWorktreeInRepository(repository.id)))
          } label: {
            Label("New Worktree", systemImage: "plus")
              .labelStyle(.iconOnly)
              .frame(maxHeight: .infinity)
              .contentShape(Rectangle())
              .background {
                if Self.debugHeaderLayers {
                  Rectangle()
                    .fill(.mint.opacity(0.18))
                    .overlay {
                      Rectangle()
                        .stroke(.mint, lineWidth: 1)
                    }
                }
              }
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help(
            AppShortcuts.helpText(
              title: "New Worktree",
              commandID: AppShortcuts.CommandID.newWorktree,
              in: resolvedKeybindings
            )
          )
          .disabled(isRemovingRepository)
        }
        if repository.capabilities.supportsWorktrees {
          Button {
            toggleExpanded()
          } label: {
            Image(systemName: "chevron.right")
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .frame(maxHeight: .infinity)
              .contentShape(Rectangle())
              .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
              .background {
                if Self.debugHeaderLayers {
                  Rectangle()
                    .fill(.orange.opacity(0.18))
                    .overlay {
                      Rectangle()
                        .stroke(.orange, lineWidth: 1)
                    }
                }
              }
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help(isExpanded ? "Collapse" : "Expand")
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: headerCellHeight, alignment: .center)
    .contentShape(.interaction, .rect)
    .background {
      if Self.debugHeaderLayers {
        Rectangle()
          .fill(.red.opacity(0.12))
          .overlay {
            Rectangle()
              .stroke(.red, lineWidth: 1)
          }
      }
    }
    .overlay(alignment: .top) {
      if showsTopSeparator && !isPlainFolderSelected {
        Rectangle()
          .fill(Self.debugHeaderLayers ? .blue : .secondary)
          .frame(height: 1)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
      }
    }
    .onHover { isHovering = $0 }
    .contentShape(.rect)
    .help(
      repository.capabilities.supportsWorktrees
        ? (isExpanded ? "Collapse" : "Expand")
        : "Open folder terminal"
    )
    .contextMenu {
      Button("Repo Settings") {
        openRepoSettings()
      }
      .help("Repo Settings ")
      Button("Remove Repository") {
        store.send(.repositoryManagement(.requestRemoveRepository(repository.id)))
      }
      .help("Remove repository ")
      .disabled(isRemovingRepository)
    }
    .contentShape(.dragPreview, .rect)
    .listRowBackground(Color.clear)
    .environment(\.colorScheme, colorScheme)
    .preferredColorScheme(colorScheme)

    Group {
      header
        .tag(SidebarSelection.repository(repository.id))
      if isExpanded {
        WorktreeRowsView(
          repository: repository,
          isExpanded: isExpanded,
          hotkeyRows: hotkeyRows,
          selectedWorktreeIDs: selectedWorktreeIDs,
          store: store,
          terminalManager: terminalManager
        )
      }
    }
  }

  private var headerCellHeight: CGFloat {
    34
  }

  static func openTabCount(
    for repository: Repository,
    terminalManager: WorktreeTerminalManager
  ) -> Int {
    if repository.capabilities.supportsWorktrees {
      return repository.worktrees.reduce(0) { count, worktree in
        count + (terminalManager.stateIfExists(for: worktree.id)?.tabManager.tabs.count ?? 0)
      }
    }
    return terminalManager.stateIfExists(for: repository.id)?.tabManager.tabs.count ?? 0
  }
}
