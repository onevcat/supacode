import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct RepositorySettingsFeatureTests {
  @Test(.dependencies) func plainFolderTaskLoadsWithoutGitRequests() async throws {
    let rootURL = URL(fileURLWithPath: "/tmp/folder-\(UUID().uuidString)")
    let settingsStorage = SettingsTestStorage()
    let localStorage = RepositoryLocalSettingsTestStorage()
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json")
    let expectedDefaultWorktreeBaseDirectoryPath =
      SupacodePaths.normalizedWorktreeBaseDirectoryPath("/tmp/worktrees")
    let storedSettings = RepositorySettings(
      setupScript: "echo setup",
      archiveScript: "echo archive",
      runScript: "npm run dev",
      openActionID: OpenWorktreeAction.automaticSettingsID,
      worktreeBaseRef: "origin/main",
      copyIgnoredOnWorktreeCreate: true,
      copyUntrackedOnWorktreeCreate: true,
      pullRequestMergeStrategy: .squash
    )
    let storedOnevcatSettings = OnevcatRepositorySettings(
      customCommands: [.default(index: 0)]
    )
    let repositoryID = rootURL.standardizedFileURL.path(percentEncoded: false)
    let bareRepositoryRequests = LockIsolated(0)
    let branchRefRequests = LockIsolated(0)
    let automaticBaseRefRequests = LockIsolated(0)
    var settingsFile = SettingsFile.default
    settingsFile.global.defaultWorktreeBaseDirectoryPath = "/tmp/worktrees"
    settingsFile.repositories[repositoryID] = storedSettings
    let settingsData = try #require(try? JSONEncoder().encode(settingsFile))
    try #require(try? settingsStorage.storage.save(settingsData, settingsFileURL))

    let onevcatSettingsData = try #require(try? JSONEncoder().encode(storedOnevcatSettings))
    try #require(
      try? localStorage.save(
        onevcatSettingsData,
        at: SupacodePaths.onevcatRepositorySettingsURL(for: rootURL)
      )
    )

    let store = TestStore(
      initialState: RepositorySettingsFeature.State(
        rootURL: rootURL,
        repositoryKind: .plain,
        settings: .default,
        onevcatSettings: .default
      )
    ) {
      RepositorySettingsFeature()
    } withDependencies: {
      $0.settingsFileStorage = settingsStorage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryLocalSettingsStorage = localStorage.storage
      $0.gitClient.isBareRepository = { _ in
        bareRepositoryRequests.withValue { $0 += 1 }
        return false
      }
      $0.gitClient.branchRefs = { _ in
        branchRefRequests.withValue { $0 += 1 }
        return []
      }
      $0.gitClient.automaticWorktreeBaseRef = { _ in
        automaticBaseRefRequests.withValue { $0 += 1 }
        return "origin/main"
      }
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded, timeout: .seconds(5)) {
      $0.settings = storedSettings
      $0.onevcatSettings = storedOnevcatSettings
      $0.globalDefaultWorktreeBaseDirectoryPath = expectedDefaultWorktreeBaseDirectoryPath
    }
    await store.finish(timeout: .seconds(5))

    #expect(store.state.isBranchDataLoaded == false)
    #expect(store.state.branchOptions.isEmpty)
    #expect(bareRepositoryRequests.value == 0)
    #expect(branchRefRequests.value == 0)
    #expect(automaticBaseRefRequests.value == 0)
  }

  @Test(.dependencies) func remoteRepositoryTaskUsesSafeEndpointAwareFallback() async throws {
    let testID = UUID().uuidString
    let rootURL = URL(fileURLWithPath: "/tmp/remote-\(testID)")
    let settingsStorage = SettingsTestStorage()
    let localStorage = RepositoryLocalSettingsTestStorage()
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(testID).json")
    let hostProfileID = "h1-\(testID)"
    let endpoint = RepositoryEndpoint.remote(
      hostProfileID: hostProfileID,
      remotePath: "/srv/\(testID)/repo"
    )
    let profile = SSHHostProfile(
      id: hostProfileID,
      displayName: "Server",
      host: "example.com",
      user: "dev",
      authMethod: .publicKey
    )
    let storedSettings = RepositorySettings(
      setupScript: "echo setup",
      archiveScript: "echo archive",
      runScript: "npm run dev",
      openActionID: OpenWorktreeAction.automaticSettingsID,
      worktreeBaseRef: "origin/remote-main",
      copyIgnoredOnWorktreeCreate: true,
      copyUntrackedOnWorktreeCreate: true,
      pullRequestMergeStrategy: .squash
    )
    let repositoryID = rootURL.standardizedFileURL.path(percentEncoded: false)
    let bareRepositoryRequests = LockIsolated(0)
    let branchRefRequests = LockIsolated(0)
    let automaticBaseRefRequests = LockIsolated(0)
    let store = withDependencies {
      $0.settingsFileStorage = settingsStorage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryLocalSettingsStorage = localStorage.storage
    } operation: {
      @Shared(.settingsFile) var settingsFile
      $settingsFile.withLock {
        $0.repositories[repositoryID] = storedSettings
        $0.sshHostProfiles = [profile]
      }
      return TestStore(
        initialState: RepositorySettingsFeature.State(
          rootURL: rootURL,
          repositoryKind: .git,
          endpoint: endpoint,
          settings: .default,
          onevcatSettings: .default
        )
      ) {
        RepositorySettingsFeature()
      } withDependencies: {
        $0.gitClient.isBareRepository = { _ in
          bareRepositoryRequests.withValue { $0 += 1 }
          return false
        }
        $0.gitClient.branchRefs = { _ in
          branchRefRequests.withValue { $0 += 1 }
          return []
        }
        $0.gitClient.automaticWorktreeBaseRef = { _ in
          automaticBaseRefRequests.withValue { $0 += 1 }
          return "origin/main"
        }
      }
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded, timeout: .seconds(5)) {
      $0.settings = storedSettings
      $0.isBareRepository = false
    }
    await store.receive(\.branchDataLoaded, timeout: .seconds(5)) {
      $0.defaultWorktreeBaseRef = "origin/remote-main"
      $0.branchOptions = ["origin/remote-main"]
      $0.isBranchDataLoaded = true
    }
    await store.finish(timeout: .seconds(5))

    #expect(bareRepositoryRequests.value == 0)
    #expect(branchRefRequests.value == 0)
    #expect(automaticBaseRefRequests.value == 0)
  }

  @Test func plainFolderVisibilityHidesGitOnlySections() {
    let state = RepositorySettingsFeature.State(
      rootURL: URL(fileURLWithPath: "/tmp/folder"),
      repositoryKind: .plain,
      settings: .default,
      onevcatSettings: .default
    )

    #expect(state.showsWorktreeSettings == false)
    #expect(state.showsPullRequestSettings == false)
    #expect(state.showsSetupScriptSettings == false)
    #expect(state.showsArchiveScriptSettings == false)
    #expect(state.showsRunScriptSettings == true)
    #expect(state.showsCustomCommandsSettings == true)
  }
}
