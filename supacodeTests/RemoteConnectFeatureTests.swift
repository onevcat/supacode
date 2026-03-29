import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteConnectFeatureTests {
  @Test func continueButtonTappedRequiresHostBeforeAdvancing() async {
    let store = TestStore(
      initialState: RemoteConnectFeature.State(savedHostProfiles: [])
    ) {
      RemoteConnectFeature()
    }

    await store.send(.continueButtonTapped) {
      $0.validationMessage = "Host required."
    }
  }

  @Test func selectingSavedHostAdvancesToRepositoryStep() async {
    let createdAt = Date(timeIntervalSince1970: 10)
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      port: 2222,
      authMethod: .publicKey,
      createdAt: createdAt,
      updatedAt: createdAt
    )
    let store = TestStore(
      initialState: RemoteConnectFeature.State(savedHostProfiles: [profile])
    ) {
      RemoteConnectFeature()
    }

    await store.send(.savedHostProfileSelected(profile.id)) {
      $0.selectedHostProfileID = profile.id
      $0.displayName = profile.displayName
      $0.host = profile.host
      $0.user = profile.user
      $0.port = "2222"
      $0.authMethod = .publicKey
    }
    await store.send(.continueButtonTapped) {
      $0.step = .repository
    }
  }

  @Test func browseRemoteFoldersNavigatesAndChoosesCurrentFolder() async {
    let commands = LockIsolated<[String]>([])
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.remoteExecutionClient.run = { _, command, _ in
        commands.withValue { $0.append(command) }
        if command.contains("/Users/deploy/src") {
          return RemoteExecutionClient.Output(
            stdout: "/Users/deploy/src\n/Users/deploy/src/project\n",
            stderr: "",
            exitCode: 0
          )
        }
        return RemoteExecutionClient.Output(
          stdout: "/Users/deploy\n/Users/deploy/src\n/Users/deploy/work\n",
          stderr: "",
          exitCode: 0
        )
      }
    }

    await store.send(.browseRemoteFoldersButtonTapped) {
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "",
        childDirectories: [],
        isLoading: true,
        errorMessage: nil
      )
    }
    await store.receive(
      .remoteDirectoryListingLoaded(
        RemoteConnectFeature.DirectoryListing(
          currentPath: "/Users/deploy",
          childDirectories: [
            "/Users/deploy/src",
            "/Users/deploy/work",
          ]
        )
      )
    ) {
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "/Users/deploy",
        childDirectories: [
          "/Users/deploy/src",
          "/Users/deploy/work",
        ],
        isLoading: false,
        errorMessage: nil
      )
    }

    await store.send(.directoryBrowserEntryTapped("/Users/deploy/src")) {
      $0.directoryBrowser?.isLoading = true
      $0.directoryBrowser?.errorMessage = nil
    }
    await store.receive(
      .remoteDirectoryListingLoaded(
        RemoteConnectFeature.DirectoryListing(
          currentPath: "/Users/deploy/src",
          childDirectories: [
            "/Users/deploy/src/project"
          ]
        )
      )
    ) {
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "/Users/deploy/src",
        childDirectories: [
          "/Users/deploy/src/project"
        ],
        isLoading: false,
        errorMessage: nil
      )
    }

    await store.send(.directoryBrowserChooseCurrentFolderButtonTapped) {
      $0.remotePath = "/Users/deploy/src"
      $0.directoryBrowser = nil
    }

    let recordedCommands = commands.value
    #expect(recordedCommands.count == 2)
  }

  @Test func connectButtonTappedValidatesRemoteRepositoryAndDelegatesSubmission() async {
    let createdAt = Date(timeIntervalSince1970: 10)
    let now = Date(timeIntervalSince1970: 20)
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      port: 2222,
      authMethod: .publicKey,
      createdAt: createdAt,
      updatedAt: createdAt
    )
    var state = RemoteConnectFeature.State(savedHostProfiles: [profile])
    state.step = .repository
    state.selectedHostProfileID = profile.id
    state.displayName = profile.displayName
    state.host = profile.host
    state.user = profile.user
    state.port = "2222"
    state.authMethod = .publicKey
    state.remotePath = "~/src/repo"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.remoteExecutionClient.run = { _, _, _ in
        RemoteExecutionClient.Output(
          stdout: "/home/deploy/src/repo\n",
          stderr: "",
          exitCode: 0
        )
      }
      $0.uuid = .incrementing
      $0.date = .constant(now)
    }

    let expectedSubmission = RemoteConnectFeature.Submission(
      hostProfile: SSHHostProfile(
        id: profile.id,
        displayName: profile.displayName,
        host: profile.host,
        user: profile.user,
        port: profile.port,
        authMethod: profile.authMethod,
        createdAt: createdAt,
        updatedAt: now
      ),
      remotePath: "/home/deploy/src/repo"
    )

    await store.send(.connectButtonTapped) {
      $0.isSubmitting = true
      $0.validationMessage = nil
    }
    await store.receive(.remoteRepositoryValidated(expectedSubmission)) {
      $0.remotePath = "/home/deploy/src/repo"
      $0.isSubmitting = false
    }
    await store.receive(.delegate(.completed(expectedSubmission)))
  }
}
