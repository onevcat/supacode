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

  private func makeWorktree(id: String, name: String) -> Worktree {
    Worktree(
      id: id,
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
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
