import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct RepositoriesFeatureTests {
  @Test func selectWorktreeSendsDelegate() async {
    let worktree = makeWorktree(id: "/tmp/wt", name: "fox")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let store = TestStore(initialState: RepositoriesFeature.State(repositories: [repository])) {
      RepositoriesFeature()
    }

    await store.send(.selectWorktree(worktree.id)) {
      $0.selectedWorktreeID = worktree.id
    }
    await store.receive(.delegate(.selectedWorktreeChanged(worktree)))
  }

  @Test func createRandomWorktreeWithoutRepositoriesShowsAlert() async {
    let store = TestStore(initialState: RepositoriesFeature.State()) {
      RepositoriesFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Unable to create worktree")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("OK")
      }
    } message: {
      TextState("Open a repository to create a worktree.")
    }

    await store.send(.createRandomWorktree) {
      $0.alert = expectedAlert
    }
  }

  @Test func requestRemoveDirtyWorktreeShowsConfirmation() async {
    let worktree = makeWorktree(id: "/tmp/wt", name: "owl")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let store = TestStore(initialState: RepositoriesFeature.State(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      $0.gitClient.isWorktreeDirty = { _ in true }
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Worktree has uncommitted changes")
    } actions: {
      ButtonState(role: .destructive, action: .confirmRemoveWorktree(worktree.id, repository.id)) {
        TextState("Remove anyway")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Remove \(worktree.name)? This deletes the worktree directory and its branch.")
    }

    await store.send(.requestRemoveWorktree(worktree.id, repository.id))
    await store.receive(.presentWorktreeRemovalConfirmation(worktree.id, repository.id)) {
      $0.alert = expectedAlert
    }
  }

  @Test func requestRenameBranchWithEmptyNameShowsAlert() async {
    let worktree = makeWorktree(id: "/tmp/wt", name: "eagle")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let store = TestStore(initialState: RepositoriesFeature.State(repositories: [repository])) {
      RepositoriesFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Branch name required")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("OK")
      }
    } message: {
      TextState("Enter a branch name to rename.")
    }

    await store.send(.requestRenameBranch(worktree.id, " ")) {
      $0.alert = expectedAlert
    }
  }

  @Test func orderedWorktreeRowsAreGlobal() {
    let repoA = makeRepository(
      id: "/tmp/repo-a",
      worktrees: [
        makeWorktree(id: "/tmp/repo-a/wt1", name: "wt1", repoRoot: "/tmp/repo-a"),
        makeWorktree(id: "/tmp/repo-a/wt2", name: "wt2", repoRoot: "/tmp/repo-a"),
      ]
    )
    let repoB = makeRepository(
      id: "/tmp/repo-b",
      worktrees: [
        makeWorktree(id: "/tmp/repo-b/wt3", name: "wt3", repoRoot: "/tmp/repo-b")
      ]
    )
    let state = RepositoriesFeature.State(repositories: [repoA, repoB])

    #expect(
      state.orderedWorktreeRows().map(\.id) == [
        "/tmp/repo-a/wt1",
        "/tmp/repo-a/wt2",
        "/tmp/repo-b/wt3",
      ]
    )
  }

  @Test func loadRepositoriesFailureKeepsPreviousState() async {
    let repository = makeRepository(id: "/tmp/repo", worktrees: [])
    let store = TestStore(initialState: RepositoriesFeature.State(repositories: [repository])) {
      RepositoriesFeature()
    }

    let expectedAlert = AlertState<RepositoriesFeature.Alert> {
      TextState("Failed to load repository")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("OK")
      }
    } message: {
      TextState("boom")
    }

    await store.send(
      .repositoriesLoaded(
        [],
        failures: [RepositoriesFeature.LoadFailure(rootID: repository.id, message: "boom")],
        roots: [repository.rootURL],
        animated: false
      )
    ) {
      $0.alert = expectedAlert
      $0.repositories = [repository]
    }

    await store.receive(.delegate(.repositoriesChanged([repository])))
  }

  @Test func repositoriesLoadedUpdatesSelectedWorktreeDelegateOnChange() async {
    let repoRoot = "/tmp/repo"
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [worktree])
    let updatedWorktree = makeWorktree(id: "/tmp/repo/main", name: "main-updated", repoRoot: repoRoot)
    let updatedRepository = makeRepository(id: repoRoot, worktrees: [updatedWorktree])
    var initialState = RepositoriesFeature.State(repositories: [repository])
    initialState.selectedWorktreeID = worktree.id
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    }

    await store.send(
      .repositoriesLoaded(
        [updatedRepository],
        failures: [],
        roots: [repository.rootURL],
        animated: false
      )
    ) {
      $0.repositories = [updatedRepository]
    }
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
    await store.receive(.delegate(.selectedWorktreeChanged(updatedWorktree)))
  }

  @Test func worktreeRemovedPrunesStateAndSendsDelegates() async {
    let repoRoot = "/tmp/repo"
    let mainWorktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: repoRoot)
    let removedWorktree = makeWorktree(id: "/tmp/repo/feature", name: "feature", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [mainWorktree, removedWorktree])
    let updatedRepository = makeRepository(id: repoRoot, worktrees: [mainWorktree])
    var initialState = RepositoriesFeature.State(repositories: [repository])
    initialState.selectedWorktreeID = mainWorktree.id
    initialState.deletingWorktreeIDs = [removedWorktree.id]
    initialState.pendingSetupScriptWorktreeIDs = [removedWorktree.id]
    initialState.pendingTerminalFocusWorktreeIDs = [removedWorktree.id]
    initialState.pendingWorktrees = [
      PendingWorktree(
        id: removedWorktree.id,
        repositoryID: repository.id,
        name: "pending",
        detail: ""
      ),
    ]
    initialState.pinnedWorktreeIDs = [removedWorktree.id]
    initialState.worktreeInfoByID = [
      removedWorktree.id: WorktreeInfoEntry(addedLines: 1, removedLines: 2, pullRequest: nil)
    ]
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.gitClient.worktrees = { _ in [mainWorktree] }
    }

    await store.send(
      .worktreeRemoved(
        removedWorktree.id,
        repositoryID: repository.id,
        selectionWasRemoved: false,
        nextSelection: nil
      )
    ) {
      $0.deletingWorktreeIDs = []
      $0.pendingSetupScriptWorktreeIDs = []
      $0.pendingTerminalFocusWorktreeIDs = []
      $0.pendingWorktrees = []
      $0.pinnedWorktreeIDs = []
      $0.worktreeInfoByID = [:]
      $0.repositories = [updatedRepository]
    }
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
    await store.receive(.reloadRepositories(animated: true))
    await store.receive(
      .repositoriesLoaded(
        [updatedRepository],
        failures: [],
        roots: [repository.rootURL],
        animated: true
      )
    )
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
  }

  @Test func worktreeRemovedResetsSelectionWhenDriftedToDeletingWorktree() async {
    let repoRoot = "/tmp/repo"
    let mainWorktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: repoRoot)
    let removedWorktree = makeWorktree(id: "/tmp/repo/feature", name: "feature", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [mainWorktree, removedWorktree])
    let updatedRepository = makeRepository(id: repoRoot, worktrees: [mainWorktree])
    var initialState = RepositoriesFeature.State(repositories: [repository])
    initialState.selectedWorktreeID = removedWorktree.id
    initialState.deletingWorktreeIDs = [removedWorktree.id]
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.gitClient.worktrees = { _ in [mainWorktree] }
    }

    await store.send(
      .worktreeRemoved(
        removedWorktree.id,
        repositoryID: repository.id,
        selectionWasRemoved: false,
        nextSelection: nil
      )
    ) {
      $0.deletingWorktreeIDs = []
      $0.repositories = [updatedRepository]
      $0.selectedWorktreeID = mainWorktree.id
    }
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
    await store.receive(.delegate(.selectedWorktreeChanged(mainWorktree)))
    await store.receive(.reloadRepositories(animated: true))
    await store.receive(
      .repositoriesLoaded(
        [updatedRepository],
        failures: [],
        roots: [repository.rootURL],
        animated: true
      )
    )
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
  }

  @Test func createRandomWorktreeSucceededSendsRepositoriesChanged() async {
    let repoRoot = "/tmp/repo"
    let existingWorktree = makeWorktree(id: "/tmp/repo/wt-main", name: "main", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [existingWorktree])
    let newWorktree = makeWorktree(id: "/tmp/repo/wt-new", name: "new", repoRoot: repoRoot)
    let updatedRepository = makeRepository(id: repoRoot, worktrees: [newWorktree, existingWorktree])
    let pendingID = "pending:\(UUID().uuidString)"
    var initialState = RepositoriesFeature.State(repositories: [repository])
    initialState.pendingWorktrees = [
      PendingWorktree(
        id: pendingID,
        repositoryID: repository.id,
        name: "Creating worktree...",
        detail: ""
      ),
    ]
    initialState.selectedWorktreeID = pendingID
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.gitClient.worktrees = { _ in [newWorktree, existingWorktree] }
    }

    await store.send(
      .createRandomWorktreeSucceeded(
        newWorktree,
        repositoryID: repository.id,
        pendingID: pendingID
      )
    ) {
      $0.pendingSetupScriptWorktreeIDs.insert(newWorktree.id)
      $0.pendingTerminalFocusWorktreeIDs.insert(newWorktree.id)
      $0.pendingWorktrees = []
      $0.selectedWorktreeID = newWorktree.id
      $0.repositories = [updatedRepository]
    }

    await store.receive(.reloadRepositories(animated: false))
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
    await store.receive(.delegate(.selectedWorktreeChanged(newWorktree)))
    await store.receive(
      .repositoriesLoaded(
        [updatedRepository],
        failures: [],
        roots: [repository.rootURL],
        animated: false
      )
    )
    await store.receive(.delegate(.repositoriesChanged([updatedRepository])))
  }

  private func makeWorktree(id: String, name: String, repoRoot: String = "/tmp/repo") -> Worktree {
    Worktree(
      id: id,
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }

  private func makeRepository(id: String, worktrees: [Worktree]) -> Repository {
    Repository(
      id: id,
      rootURL: URL(fileURLWithPath: id),
      name: "repo",
      worktrees: worktrees
    )
  }
}
