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
      $0.openedWorktreeIDs = [worktree.id]
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
      $0.openedWorktreeIDs = [worktree.id]
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
      $0.openedWorktreeIDs = [worktree.id]
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
      $0.openedWorktreeIDs = [second.id]
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

  @Test(.dependencies) func selectShelfBookByIndexDispatchesWorktreeSelection() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let wt1 = Worktree(
      id: "/tmp/repo",
      name: "main",
      detail: "",
      workingDirectory: rootURL,
      repositoryRootURL: rootURL
    )
    let wt2 = Worktree(
      id: "/tmp/repo/feature",
      name: "feature",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRootURL: rootURL
    )
    let repo = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [wt1, wt2])
    )
    var state = RepositoriesFeature.State(repositories: [repo])
    state.repositoryRoots = [rootURL]
    state.repositoryOrderIDs = [repo.id]
    state.selection = .worktree(wt1.id)
    state.isShelfActive = true
    state.openedWorktreeIDs = [wt1.id, wt2.id]
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.selectShelfBook(2))
    await store.receive(\.selectWorktree) {
      $0.selection = .worktree(wt2.id)
      $0.sidebarSelectedWorktreeIDs = [wt2.id]
      $0.pendingTerminalFocusWorktreeIDs = [wt2.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }

  @Test(.dependencies) func selectShelfBookOutOfRangeIsNoOp() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let wt1 = Worktree(
      id: "/tmp/repo",
      name: "main",
      detail: "",
      workingDirectory: rootURL,
      repositoryRootURL: rootURL
    )
    let repo = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [wt1])
    )
    var state = RepositoriesFeature.State(repositories: [repo])
    state.repositoryRoots = [rootURL]
    state.repositoryOrderIDs = [repo.id]
    state.selection = .worktree(wt1.id)
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.selectShelfBook(5))
    await store.finish()
  }

  @Test(.dependencies) func selectNextShelfBookWrapsAround() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let wt1 = Worktree(
      id: "/tmp/repo",
      name: "main",
      detail: "",
      workingDirectory: rootURL,
      repositoryRootURL: rootURL
    )
    let wt2 = Worktree(
      id: "/tmp/repo/feature",
      name: "feature",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRootURL: rootURL
    )
    let repo = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [wt1, wt2])
    )
    var state = RepositoriesFeature.State(repositories: [repo])
    state.repositoryRoots = [rootURL]
    state.repositoryOrderIDs = [repo.id]
    state.selection = .worktree(wt2.id)  // Currently on the last book.
    state.openedWorktreeIDs = [wt1.id, wt2.id]
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.selectNextShelfBook)
    // Wrapping: next-after-last lands back on the first book.
    await store.receive(\.selectWorktree) {
      $0.selection = .worktree(wt1.id)
      $0.sidebarSelectedWorktreeIDs = [wt1.id]
      $0.pendingTerminalFocusWorktreeIDs = [wt1.id]
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.finish()
  }

  @Test(.dependencies) func markWorktreeOpenedAddsToOpenedSet() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let wt1 = Worktree(
      id: "/tmp/repo/wt1",
      name: "wt1",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt1"),
      repositoryRootURL: rootURL
    )
    let repo = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [wt1])
    )
    let store = TestStore(initialState: RepositoriesFeature.State(repositories: [repo])) {
      RepositoriesFeature()
    }

    // Mirrors the AppFeature forwarding `terminalEvent(.tabCreated)` →
    // `.markWorktreeOpened`. Any tab creation (including restored
    // layouts) adds its worktree to the Shelf's visible book set.
    await store.send(.markWorktreeOpened(wt1.id)) {
      $0.openedWorktreeIDs = [wt1.id]
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
