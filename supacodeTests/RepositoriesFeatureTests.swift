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
