//
//  ContentView.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import Kingfisher
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  let runtime: GhosttyRuntime
  @Environment(RepositoryStore.self) private var repositoryStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var terminalStore: WorktreeTerminalStore
  @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
    _terminalStore = State(initialValue: WorktreeTerminalStore(runtime: runtime))
  }

  var body: some View {
    @Bindable var repositoryStore = repositoryStore
    let selectedRow = repositoryStore.selectedRow(for: repositoryStore.selectedWorktreeID)
    let selectedWorktree = repositoryStore.worktree(for: repositoryStore.selectedWorktreeID)
    let loadingInfo: WorktreeLoadingInfo? = {
      guard let selectedRow else { return nil }
      let repositoryName = repositoryStore.repositoryName(for: selectedRow.repositoryID)
      if selectedRow.isDeleting {
        return WorktreeLoadingInfo(
          name: selectedRow.name,
          repositoryName: repositoryName,
          state: .removing
        )
      }
      if selectedRow.isPending {
        return WorktreeLoadingInfo(
          name: selectedRow.name,
          repositoryName: repositoryName,
          state: .creating
        )
      }
      return nil
    }()
    NavigationSplitView(columnVisibility: $sidebarVisibility) {
      SidebarView(
        repositories: repositoryStore.repositories,
        pendingWorktrees: repositoryStore.pendingWorktrees,
        selection: $repositoryStore.selectedWorktreeID,
        createWorktree: { repository in
          Task {
            await repositoryStore.createRandomWorktree(in: repository)
          }
        }
      )
    } detail: {
      WorktreeDetailView(
        selectedWorktree: selectedWorktree,
        loadingInfo: loadingInfo,
        terminalStore: terminalStore,
        toggleSidebar: toggleSidebar
      )
    }
    .navigationSplitViewStyle(.balanced)
    .onChange(of: scenePhase) { _, newValue in
      guard newValue == .active else { return }
      Task {
        await repositoryStore.loadPersistedRepositories()
      }
    }
    .onChange(of: repositoryStore.repositories) { _, newValue in
      var worktreeIDs: Set<Worktree.ID> = []
      for repository in newValue {
        for worktree in repository.worktrees {
          worktreeIDs.insert(worktree.id)
        }
      }
      terminalStore.prune(keeping: worktreeIDs)
    }
    .fileImporter(
      isPresented: $repositoryStore.isOpenPanelPresented,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        Task {
          await repositoryStore.openRepositories(at: urls)
        }
      case .failure:
        repositoryStore.alert = AppAlert(
          id: UUID(),
          title: "Unable to open folders",
          message: "Supacode could not read the selected folders."
        )
      }
    }
    .alert(item: $repositoryStore.alert) { error in
      Alert(
        title: Text(error.title),
        message: Text(error.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .focusedSceneValue(\.toggleSidebarAction, toggleSidebar)
  }

  private func toggleSidebar() {
    withAnimation(.easeInOut(duration: 0.2)) {
      sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
    }
  }
}

private struct WorktreeDetailView: View {
  let selectedWorktree: Worktree?
  let loadingInfo: WorktreeLoadingInfo?
  let terminalStore: WorktreeTerminalStore
  let toggleSidebar: () -> Void
  @State private var openActionError: OpenActionError?
  @State private var openActionSelection: OpenWorktreeAction = .finder
  private let settingsStore = RepositorySettingsStore()

  var body: some View {
    Group {
      if let loadingInfo {
        WorktreeLoadingView(info: loadingInfo)
      } else if let selectedWorktree {
        WorktreeTerminalTabsView(worktree: selectedWorktree, store: terminalStore)
          .id(selectedWorktree.id)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        EmptyStateView()
      }
    }
    .navigationTitle(selectedWorktree?.name ?? loadingInfo?.name ?? "Supacode")
    .toolbar {
      let isOpenDisabled = selectedWorktree == nil || loadingInfo != nil
      let openActionHelpText =
        "\(openActionSelection.title) (\(AppShortcuts.openFinder.display))"
      if !isOpenDisabled {
        ToolbarItemGroup(placement: .primaryAction) {
          Menu {
            ForEach(OpenWorktreeAction.allCases) { action in
              let isDefault = action == openActionSelection
              Button {
                setOpenActionSelection(action)
                performOpenAction(action)
              } label: {
                if let appIcon = action.appIcon {
                  Label {
                    Text(action.title)
                  } icon: {
                    Image(nsImage: appIcon)
                      .accessibilityHidden(true)
                  }
                } else {
                  Label(action.title, systemImage: "app")
                }
              }
              .modifier(
                OpenActionShortcutModifier(
                  shortcut: isDefault ? AppShortcuts.openFinder : nil
                )
              )
              .help(
                isDefault
                  ? "\(action.title) (\(AppShortcuts.openFinder.display))"
                  : action.title
              )
            }
          } label: {
            Label {
              Text("Open")
            } icon: {
              if let appIcon = openActionSelection.appIcon {
                Image(nsImage: appIcon)
                  .resizable()
                  .scaledToFit()
                  .accessibilityHidden(true)
              } else {
                Image(systemName: "folder")
                  .resizable()
                  .scaledToFit()
                  .accessibilityHidden(true)
              }
            }
          }
          .help(openActionHelpText)
        }
      }
    }
    .alert(item: $openActionError) { error in
      Alert(
        title: Text(error.title),
        message: Text(error.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .onAppear {
      loadOpenActionSelection()
    }
    .onChange(of: selectedWorktree?.repositoryRootURL) { _, _ in
      loadOpenActionSelection()
    }
    .focusedSceneValue(
      \.newTerminalAction,
      {
        guard let selectedWorktree else { return }
        terminalStore.createTab(in: selectedWorktree)
      }
    )
    .focusedSceneValue(
      \.closeTabAction,
      {
        guard let selectedWorktree else { return }
        terminalStore.closeFocusedTab(in: selectedWorktree)
      }
    )
    .focusedSceneValue(
      \.closeSurfaceAction,
      {
        guard let selectedWorktree else { return }
        terminalStore.closeFocusedSurface(in: selectedWorktree)
      }
    )
  }

  private func performOpenAction(_ action: OpenWorktreeAction) {
    guard let selectedWorktree else { return }
    action.perform(with: selectedWorktree) { error in
      openActionError = error
    }
  }

  private func loadOpenActionSelection() {
    guard let selectedWorktree else {
      openActionSelection = .finder
      return
    }
    let settings = settingsStore.load(for: selectedWorktree.repositoryRootURL)
    openActionSelection = OpenWorktreeAction.fromSettingsID(settings.openActionID)
  }

  private func setOpenActionSelection(_ action: OpenWorktreeAction) {
    openActionSelection = action
    guard let selectedWorktree else { return }
    var settings = settingsStore.load(for: selectedWorktree.repositoryRootURL)
    settings.openActionID = action.settingsID
    settingsStore.save(settings, for: selectedWorktree.repositoryRootURL)
  }
}

private struct SidebarView: View {
  let repositories: [Repository]
  let pendingWorktrees: [PendingWorktree]
  @Binding var selection: Worktree.ID?
  let createWorktree: (Repository) -> Void
  @Environment(RepositoryStore.self) private var repositoryStore
  @State private var expandedRepoIDs: Set<Repository.ID>
  @State private var pendingRemoval: PendingWorktreeRemoval?
  @State private var pendingRepositoryRemoval: PendingRepositoryRemoval?

  init(
    repositories: [Repository],
    pendingWorktrees: [PendingWorktree],
    selection: Binding<Worktree.ID?>,
    createWorktree: @escaping (Repository) -> Void
  ) {
    self.repositories = repositories
    self.pendingWorktrees = pendingWorktrees
    _selection = selection
    self.createWorktree = createWorktree
    let repositoryIDs = Set(repositories.map(\.id))
    let pendingRepositoryIDs = Set(pendingWorktrees.map(\.repositoryID))
    _expandedRepoIDs = State(initialValue: repositoryIDs.union(pendingRepositoryIDs))
  }

  var body: some View {
    let selectedRow = repositoryStore.selectedRow(for: selection)
    let removeWorktreeAction: (() -> Void)? = {
      guard let selectedRow, selectedRow.isRemovable else { return nil }
      return removeSelectedWorktree
    }()
    SidebarListView(
      repositories: repositories,
      pendingWorktrees: pendingWorktrees,
      selection: $selection,
      expandedRepoIDs: $expandedRepoIDs,
      createWorktree: createWorktree,
      onRequestRemoval: requestRemoval,
      onRequestRepositoryRemoval: requestRepositoryRemoval
    )
    .focusedSceneValue(\.removeWorktreeAction, removeWorktreeAction)
    .alert(item: $pendingRemoval) { candidate in
      Alert(
        title: Text("Worktree has uncommitted changes"),
        message: Text(
          "Remove \(candidate.worktree.name)? "
            + "This deletes the worktree directory and its branch."
        ),
        primaryButton: .destructive(Text("Remove anyway")) {
          Task {
            await repositoryStore.removeWorktree(
              candidate.worktree, from: candidate.repository, force: true)
          }
        },
        secondaryButton: .cancel()
      )
    }
    .alert(item: $pendingRepositoryRemoval) { candidate in
      Alert(
        title: Text("Remove repository?"),
        message: Text(
          "This removes the repository from Supacode and deletes all of its worktrees "
            + "and their branches created by Supacode. "
            + "The main repository folder is not deleted."
        ),
        primaryButton: .destructive(Text("Remove repository")) {
          Task {
            await repositoryStore.removeRepository(candidate.repository)
          }
        },
        secondaryButton: .cancel()
      )
    }
  }

  private func requestRemoval(_ worktree: Worktree, in repository: Repository) {
    Task {
      let isDirty = await repositoryStore.isWorktreeDirty(worktree)
      if isDirty {
        pendingRemoval = PendingWorktreeRemoval(repository: repository, worktree: worktree)
      } else {
        await repositoryStore.removeWorktree(worktree, from: repository, force: true)
      }
    }
  }

  private func removeSelectedWorktree() {
    guard let selection else { return }
    for repository in repositories {
      if let worktree = repository.worktrees.first(where: { $0.id == selection }) {
        requestRemoval(worktree, in: repository)
        return
      }
    }
  }

  private func requestRepositoryRemoval(_ repository: Repository) {
    if repositoryStore.isRemovingRepository(repository) {
      return
    }
    pendingRepositoryRemoval = PendingRepositoryRemoval(repository: repository)
  }
}

private struct SidebarListView: View {
  let repositories: [Repository]
  let pendingWorktrees: [PendingWorktree]
  @Binding var selection: Worktree.ID?
  @Binding var expandedRepoIDs: Set<Repository.ID>
  let createWorktree: (Repository) -> Void
  let onRequestRemoval: (Worktree, Repository) -> Void
  let onRequestRepositoryRemoval: (Repository) -> Void
  @Environment(RepositoryStore.self) private var repositoryStore

  var body: some View {
    List(selection: $selection) {
      ForEach(repositories) { repository in
        RepositorySectionView(
          repository: repository,
          expandedRepoIDs: $expandedRepoIDs,
          createWorktree: createWorktree,
          onRequestRemoval: onRequestRemoval,
          onRequestRepositoryRemoval: onRequestRepositoryRemoval
        )
      }
    }
    .listStyle(.sidebar)
    .frame(minWidth: 220)
    .onChange(of: repositories) { _, newValue in
      let current = Set(newValue.map(\.id))
      expandedRepoIDs.formUnion(current)
      expandedRepoIDs = expandedRepoIDs.intersection(current)
    }
    .onChange(of: pendingWorktrees) { _, newValue in
      let repositoryIDs = Set(newValue.map(\.repositoryID))
      expandedRepoIDs.formUnion(repositoryIDs)
    }
    .dropDestination(for: URL.self) { urls, _ in
      let fileURLs = urls.filter(\.isFileURL)
      guard !fileURLs.isEmpty else { return false }
      Task {
        await repositoryStore.openRepositories(at: fileURLs)
      }
      return true
    }
  }
}

private struct RepositorySectionView: View {
  let repository: Repository
  @Binding var expandedRepoIDs: Set<Repository.ID>
  let createWorktree: (Repository) -> Void
  let onRequestRemoval: (Worktree, Repository) -> Void
  let onRequestRepositoryRemoval: (Repository) -> Void
  @Environment(RepositoryStore.self) private var repositoryStore
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    let isExpanded = expandedRepoIDs.contains(repository.id)
    let isRemovingRepository = repositoryStore.isRemovingRepository(repository)
    let openRepoSettings = {
      openWindow(id: WindowIdentifiers.repoSettings, value: repository.id)
    }
    Section {
      WorktreeRowsView(
        repository: repository,
        isExpanded: isExpanded,
        onRequestRemoval: onRequestRemoval
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
            profileURL: repository.githubOwner.flatMap {
              Github.profilePictureURL(username: $0, size: 48)
            },
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
            onRequestRepositoryRemoval(repository)
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
        } label: {
          Label("Repository options", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Repository options (no shortcut)")
        .disabled(isRemovingRepository)
        Button("New Worktree", systemImage: "plus") {
          createWorktree(repository)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.trailing, 6)
        .help("New Worktree (\(AppShortcuts.newWorktree.display))")
        .disabled(isRemovingRepository)
      }
      .padding()
      .padding(.bottom, 6)
    }
  }
}

private struct WorktreeRowsView: View {
  let repository: Repository
  let isExpanded: Bool
  let onRequestRemoval: (Worktree, Repository) -> Void
  @Environment(RepositoryStore.self) private var repositoryStore

  var body: some View {
    if isExpanded {
      let rows = repositoryStore.worktreeRows(in: repository)
      let isRepositoryRemoving = repositoryStore.isRemovingRepository(repository)
      ForEach(rows) { row in
        rowView(row, isRepositoryRemoving: isRepositoryRemoving)
      }
    }
  }

  @ViewBuilder
  private func rowView(_ row: WorktreeRowModel, isRepositoryRemoving: Bool) -> some View {
    let displayDetail = row.isDeleting ? "Removing..." : row.detail
    if row.isRemovable, let worktree = repositoryStore.worktree(for: row.id),
      !isRepositoryRemoving
    {
      WorktreeRow(
        name: row.name,
        detail: displayDetail,
        isPinned: row.isPinned,
        isLoading: row.isPending || row.isDeleting
      )
      .tag(row.id)
      .contextMenu {
        if row.isPinned {
          Button("Unpin") {
            repositoryStore.unpinWorktree(worktree)
          }
          .help("Unpin (no shortcut)")
        } else {
          Button("Pin to top") {
            repositoryStore.pinWorktree(worktree)
          }
          .help("Pin to top (no shortcut)")
        }
        Button("Remove") {
          onRequestRemoval(worktree, repository)
        }
        .help("Remove worktree (⌘⌫)")
      }
    } else {
      WorktreeRow(
        name: row.name,
        detail: displayDetail,
        isPinned: row.isPinned,
        isLoading: row.isPending || row.isDeleting
      )
      .tag(row.id)
      .disabled(isRepositoryRemoving)
    }
  }
}

private struct PendingWorktreeRemoval: Identifiable, Hashable {
  let id: Worktree.ID
  let repository: Repository
  let worktree: Worktree

  init(repository: Repository, worktree: Worktree) {
    self.id = worktree.id
    self.repository = repository
    self.worktree = worktree
  }
}

private struct PendingRepositoryRemoval: Identifiable, Hashable {
  let id: Repository.ID
  let repository: Repository

  init(repository: Repository) {
    self.id = repository.id
    self.repository = repository
  }
}

private struct RepoHeaderRow: View {
  let name: String
  let initials: String
  let profileURL: URL?
  let isExpanded: Bool
  let isRemoving: Bool

  var body: some View {
    HStack {
      Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.secondary.opacity(0.2))
        if let profileURL {
          KFImage(profileURL)
            .resizable()
            .placeholder {
              Text(initials)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .scaledToFill()
        } else {
          Text(initials)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 24, height: 24)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      Text(name)
        .font(.headline)
        .foregroundStyle(.primary)
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct WorktreeRow: View {
  let name: String
  let detail: String
  let isPinned: Bool
  let isLoading: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      ZStack {
        Image(systemName: "arrow.triangle.branch")
          .font(.caption)
          .foregroundStyle(.secondary)
          .opacity(isLoading ? 0 : 1)
          .accessibilityHidden(true)
        if isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
        Text(detail.isEmpty ? " " : detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .opacity(detail.isEmpty ? 0 : 1)
      }
      Spacer(minLength: 8)
      if isPinned {
        Image(systemName: "pin.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
  }
}

private enum WorktreeLoadingState {
  case creating
  case removing
}

private struct WorktreeLoadingInfo: Hashable {
  let name: String
  let repositoryName: String?
  let state: WorktreeLoadingState
}

private struct WorktreeLoadingView: View {
  let info: WorktreeLoadingInfo

  var body: some View {
    let actionLabel = info.state == .creating ? "Creating" : "Removing"
    let followup =
      info.state == .creating
      ? "We will open the terminal when it's ready."
      : "We will close the terminal when it's ready."
    VStack {
      ProgressView()
      Text(info.name)
        .font(.headline)
      if let repositoryName = info.repositoryName {
        Text("\(actionLabel) worktree in \(repositoryName)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        Text("\(actionLabel) worktree...")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Text(followup)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
  }
}

private struct EmptyStateView: View {
  @Environment(RepositoryStore.self) private var repositoryStore

  var body: some View {
    VStack {
      Image(systemName: "tray")
        .font(.title2)
        .accessibilityHidden(true)
      Text("Open a git repository")
        .font(.headline)
      Text(
        "Press \(AppShortcuts.openRepository.display) "
          + "or click Open Repository to choose a repository."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      Button("Open Repository...") {
        repositoryStore.isOpenPanelPresented = true
      }
      .keyboardShortcut(
        AppShortcuts.openRepository.keyEquivalent,
        modifiers: AppShortcuts.openRepository.modifiers
      )
      .help("Open Repository (\(AppShortcuts.openRepository.display))")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .multilineTextAlignment(.center)
  }
}

private struct OpenActionShortcutModifier: ViewModifier {
  let shortcut: AppShortcut?

  func body(content: Content) -> some View {
    if let shortcut {
      content.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    } else {
      content
    }
  }
}
