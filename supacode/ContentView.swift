//
//  ContentView.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let runtime: GhosttyRuntime
    @Environment(RepositoryStore.self) private var repositoryStore
    @State private var terminalStore: WorktreeTerminalStore

    init(runtime: GhosttyRuntime) {
        self.runtime = runtime
        _terminalStore = State(initialValue: WorktreeTerminalStore(runtime: runtime))
    }

    var body: some View {
        @Bindable var repositoryStore = repositoryStore
        let selectedWorktree = repositoryStore.worktree(for: repositoryStore.selectedWorktreeID)
        NavigationSplitView {
            SidebarView(repositories: repositoryStore.repositories, selection: $repositoryStore.selectedWorktreeID)
        } detail: {
            Group {
                if let selectedWorktree {
                    WorktreeTerminalTabsView(worktree: selectedWorktree, store: terminalStore)
                        .id(selectedWorktree.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView()
                }
            }
            .navigationTitle(selectedWorktree?.name ?? "Supacode")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Sidebar", systemImage: "sidebar.left", action: {})
                    Button("Compose", systemImage: "square.and.pencil", action: {})
                    Button("Settings", systemImage: "gearshape", action: {})
                }
            }
            .focusedSceneValue(\.newTerminalAction, {
                guard let selectedWorktree else { return }
                terminalStore.createTab(in: selectedWorktree)
            })
        }
        .navigationSplitViewStyle(.balanced)
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
                repositoryStore.openError = OpenRepositoryError(
                    id: UUID(),
                    title: "Unable to open folders",
                    message: "Supacode could not read the selected folders."
                )
            }
        }
        .alert(item: $repositoryStore.openError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct SidebarView: View {
    let repositories: [Repository]
    @Binding var selection: Worktree.ID?
    @State private var expandedRepoIDs: Set<Repository.ID>

    init(repositories: [Repository], selection: Binding<Worktree.ID?>) {
        self.repositories = repositories
        _selection = selection
        _expandedRepoIDs = State(initialValue: Set(repositories.map(\.id)))
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(repositories) { repository in
                Section {
                    if expandedRepoIDs.contains(repository.id) {
                        ForEach(repository.worktrees) { worktree in
                            WorktreeRow(name: worktree.name, detail: worktree.detail)
                                .tag(worktree.id)
                        }
                    }
                } header: {
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
                            isExpanded: expandedRepoIDs.contains(repository.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .onChange(of: repositories) { _, newValue in
            let current = Set(newValue.map(\.id))
            expandedRepoIDs.formUnion(current)
            expandedRepoIDs = expandedRepoIDs.intersection(current)
        }
    }
}

private struct RepoHeaderRow: View {
    let name: String
    let initials: String
    let isExpanded: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .fill(.secondary.opacity(0.2))
                Text(initials)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            Text(name)
                .font(.headline)
        }
    }
}

private struct WorktreeRow: View {
    let name: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyStateView: View {
    @Environment(RepositoryStore.self) private var repositoryStore

    var body: some View {
        VStack {
            Image(systemName: "tray")
                .font(.title2)
            Text("Open a project or worktree")
                .font(.headline)
            Text("Press Cmd+O or click Open to choose a repository.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open...") {
                repositoryStore.isOpenPanelPresented = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .multilineTextAlignment(.center)
    }
}
