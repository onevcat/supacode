import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct RepositorySectionViewTests {
  @Test func sidebarHeaderActionCollapsesWhenAnyExpandableRepositoryIsOpen() {
    let gitRepository = Repository(
      id: "/tmp/git",
      rootURL: URL(fileURLWithPath: "/tmp/git"),
      name: "git",
      kind: .git,
      worktrees: []
    )
    let plainRepository = Repository(
      id: "/tmp/plain",
      rootURL: URL(fileURLWithPath: "/tmp/plain"),
      name: "plain",
      kind: .plain,
      worktrees: []
    )
    let expandableIDs = SidebarListView.expandableRepositoryIDs(
      in: [gitRepository, plainRepository]
    )

    #expect(expandableIDs == [gitRepository.id])
    #expect(
      SidebarListView.repositoryListHeaderAction(
        expandedRepoIDs: [],
        expandableRepositoryIDs: []
      )
        == .expandAll
    )
    #expect(
      SidebarListView.repositoryListHeaderAction(
        expandedRepoIDs: [],
        expandableRepositoryIDs: expandableIDs
      )
        == .expandAll
    )
    #expect(
      SidebarListView.repositoryListHeaderAction(
        expandedRepoIDs: [gitRepository.id],
        expandableRepositoryIDs: expandableIDs
      )
        == .collapseAll
    )
    #expect(
      SidebarListView.repositoryListHeaderAction(
        expandedRepoIDs: [gitRepository.id, plainRepository.id],
        expandableRepositoryIDs: expandableIDs
      )
        == .collapseAll
    )
    #expect(
      SidebarListView.repositoryListHeaderAction(
        expandedRepoIDs: [plainRepository.id],
        expandableRepositoryIDs: expandableIDs
      )
        == .expandAll
    )
  }

  @Test func sidebarHeaderOnlyShowsForLongRepositoryLists() {
    #expect(!SidebarListView.showsRepositoryListHeader(repositoryCount: 0))
    #expect(!SidebarListView.showsRepositoryListHeader(repositoryCount: 10))
    #expect(SidebarListView.showsRepositoryListHeader(repositoryCount: 11))
  }

  @Test func openTabCountForGitRepositorySumsAllWorktrees() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let repositoryRootURL = URL(fileURLWithPath: "/tmp/repo")
    let mainWorktree = Worktree(
      id: "/tmp/repo/main",
      name: "main",
      detail: "main",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/main"),
      repositoryRootURL: repositoryRootURL
    )
    let featureWorktree = Worktree(
      id: "/tmp/repo/feature",
      name: "feature",
      detail: "feature",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRootURL: repositoryRootURL
    )
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: repositoryRootURL,
      name: "repo",
      kind: .git,
      worktrees: IdentifiedArray(uniqueElements: [mainWorktree, featureWorktree])
    )

    let mainState = manager.state(for: mainWorktree)
    let featureState = manager.state(for: featureWorktree)
    _ = mainState.tabManager.createTab(title: "main 1", icon: nil)
    _ = mainState.tabManager.createTab(title: "main 2", icon: nil)
    _ = featureState.tabManager.createTab(title: "feature 1", icon: nil)

    #expect(
      RepositorySectionView.openTabCount(for: repository, terminalManager: manager)
        == 3
    )
  }

  @Test func openTabCountForPlainFolderUsesRepositoryIDTerminalState() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let repositoryRootURL = URL(fileURLWithPath: "/tmp/folder")
    let repository = Repository(
      id: "/tmp/folder",
      rootURL: repositoryRootURL,
      name: "folder",
      kind: .plain,
      worktrees: []
    )
    let terminalTarget = Worktree(
      id: repository.id,
      name: repository.name,
      detail: repository.rootURL.path(percentEncoded: false),
      workingDirectory: repository.rootURL,
      repositoryRootURL: repository.rootURL
    )

    let state = manager.state(for: terminalTarget)
    _ = state.tabManager.createTab(title: "folder 1", icon: nil)
    _ = state.tabManager.createTab(title: "folder 2", icon: nil)

    #expect(
      RepositorySectionView.openTabCount(for: repository, terminalManager: manager)
        == 2
    )
  }
}
