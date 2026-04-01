import ComposableArchitecture
import Testing

@testable import supacode

@MainActor
struct AppFeatureRemoteGroupsIntegrationTests {
  @Test func app_routes_remote_groups_actions() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.remoteGroups(.setAddPromptPresented(true))) {
      $0.remoteGroups.isAddPromptPresented = true
    }
  }
}
