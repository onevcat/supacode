import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteSessionPickerFeatureTests {
  @Test func attachTappedDelegatesSelectedSession() async {
    let store = TestStore(
      initialState: RemoteSessionPickerFeature.State(
        worktreeID: "wt-1",
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
        remotePath: "/srv/repo",
        sessions: ["alpha", "beta"],
        preferredSessionName: "beta",
        suggestedManagedSessionName: nil
      )
    ) {
      RemoteSessionPickerFeature()
    }

    await store.send(.attachTapped)
    await store.receive(.delegate(.attachExisting("beta")))
  }

  @Test func createAndAttachTappedTrimsSessionName() async {
    var state = RemoteSessionPickerFeature.State(
      worktreeID: "wt-1",
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
      remotePath: "/srv/repo",
      sessions: ["alpha"],
      preferredSessionName: nil,
      suggestedManagedSessionName: nil
    )
    state.managedSessionName = "  new-session  "
    let store = TestStore(initialState: state) {
      RemoteSessionPickerFeature()
    }

    await store.send(.createAndAttachTapped)
    await store.receive(.delegate(.createAndAttach("new-session")))
  }
}
