import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct ShelfFeatureTests {
  @Test(.dependencies) func toggleShelfFromWorktreeEntersShelfWithoutRedirecting() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.toggleShelf) {
      $0.isShelfActive = true
    }
    await store.finish()
  }

  @Test(.dependencies) func toggleShelfWhileActiveExitsShelf() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.isShelfActive = true
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.toggleShelf) {
      $0.isShelfActive = false
    }
    await store.finish()
  }

  @Test(.dependencies) func toggleShelfWithoutWorktreesIsNoOp() async {
    let store = TestStore(initialState: RepositoriesFeature.State()) {
      RepositoriesFeature()
    }

    await store.send(.toggleShelf)
    await store.finish()
  }

  @Test(.dependencies) func toggleShelfFromCanvasRedirectsToWorktreeAndEntersShelf() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .canvas
    state.lastFocusedWorktreeID = worktree.id
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.toggleShelf) {
      $0.isShelfActive = true
    }
    await store.receive(\.selectWorktree) {
      $0.selection = .worktree(worktree.id)
      $0.sidebarSelectedWorktreeIDs = [worktree.id]
      $0.pendingTerminalFocusWorktreeIDs = [worktree.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }

  @Test(.dependencies) func toggleShelfFromArchivedRedirectsToWorktreeAndEntersShelf() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .archivedWorktrees
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.toggleShelf) {
      $0.isShelfActive = true
    }
    await store.receive(\.selectWorktree) {
      $0.selection = .worktree(worktree.id)
      $0.sidebarSelectedWorktreeIDs = [worktree.id]
      $0.pendingTerminalFocusWorktreeIDs = [worktree.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }

  @Test(.dependencies) func selectingADifferentWorktreeKeepsShelfActive() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let first = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let second = Worktree(
      id: "/tmp/repo/wt2",
      name: "wt2",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt2"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [first, second])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(first.id)
    state.isShelfActive = true
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    // Mirrors "user clicks second worktree in the left navigation
    // while in Shelf mode": Shelf must not exit; only the open book
    // changes via the new `selectedWorktreeID`.
    await store.send(.selectWorktree(second.id, focusTerminal: true)) {
      $0.selection = .worktree(second.id)
      $0.sidebarSelectedWorktreeIDs = [second.id]
      $0.pendingTerminalFocusWorktreeIDs = [second.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }

  @Test(.dependencies) func selectCanvasClearsShelfActiveFlag() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.isShelfActive = true
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.send = { _ in }
    }

    await store.send(.selectCanvas) {
      $0.preCanvasWorktreeID = worktree.id
      $0.preCanvasTerminalTargetID = worktree.id
      $0.isShelfActive = false
      $0.selection = .canvas
      $0.sidebarSelectedWorktreeIDs = []
    }
    await store.finish()
  }

  @Test(.dependencies) func selectArchivedWorktreesClearsShelfActiveFlag() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.isShelfActive = true
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.selectArchivedWorktrees) {
      $0.isShelfActive = false
      $0.selection = .archivedWorktrees
      $0.sidebarSelectedWorktreeIDs = []
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }
}
