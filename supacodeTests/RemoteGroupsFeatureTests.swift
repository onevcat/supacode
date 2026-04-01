import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteGroupsFeatureTests {
  @Test(.dependencies) func submit_endpoint_fetches_and_groups() async throws {
    let store = TestStore(initialState: RemoteGroupsFeature.State()) {
      RemoteGroupsFeature()
    } withDependencies: {
      $0.remoteTerminalClient.listSessions = { _ in
        [
          .init(id: "1", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:1", cwd: "~", updatedAt: ""),
          .init(id: "2", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:2", cwd: "~", updatedAt: ""),
          .init(id: "3", scope: "other", reuseKey: "other:ignored:1", cwd: "~", updatedAt: ""),
        ]
      }
    }
    store.exhaustivity = .off

    await store.send(.submitEndpoint(urlText: "https://example.com/mini-terminal/", initialGroup: ""))

    let endpointID = try #require(store.state.endpoints.first?.id)
    #expect(store.state.selection == .overview(endpointID: endpointID))

    await store.receive(\.fetchEndpointSessions)
    #expect(store.state.loadingEndpointIDs.contains(endpointID))

    await store.receive(/RemoteGroupsFeature.Action.endpointSessionsResponse)
    #expect(!store.state.loadingEndpointIDs.contains(endpointID))
    #expect(
      store.state.groupsByEndpointID[endpointID] == [
        RemoteGroupRef(group: "alpha", sessionCount: 2)
      ]
    )
    #expect(store.state.errorByEndpointID[endpointID] == nil)
  }
}
