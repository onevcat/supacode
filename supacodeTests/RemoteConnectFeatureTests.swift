import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

nonisolated final class StringDictionaryRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]

  func set(_ key: String, value: String) {
    lock.lock()
    values[key] = value
    lock.unlock()
  }

  func snapshot() -> [String: String] {
    lock.lock()
    let snapshot = values
    lock.unlock()
    return snapshot
  }
}

nonisolated final class StringArrayRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  func append(_ value: String) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    let snapshot = values
    lock.unlock()
    return snapshot
  }
}

nonisolated final class IntRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }

  func snapshot() -> Int {
    lock.lock()
    let snapshot = value
    lock.unlock()
    return snapshot
  }
}

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

  @Test func continueButtonTappedRequiresPasswordWhenPasswordAuthIsSelected() async {
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.host = "example.com"
    state.user = "deploy"
    state.authMethod = .password

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 1))
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
      $0.keychainClient = .testValue
    }

    await store.send(.continueButtonTapped) {
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000123"
    }
    await store.receive(.hostValidationFailed("Password required.")) {
      $0.validationMessage = "Password required."
    }
  }

  @Test func continueButtonTappedSavesPasswordAndAdvancesWhenPasswordAuthIsSelected() async {
    let savedPasswords = StringDictionaryRecorder()
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.host = "example.com"
    state.user = "deploy"
    state.authMethod = .password
    state.password = "secret"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 2))
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
      $0.keychainClient = KeychainClient(
        savePassword: { password, key in
          savedPasswords.set(key, value: password)
        },
        loadPassword: { key in
          savedPasswords.snapshot()[key]
        },
        deletePassword: { _ in }
      )
    }

    await store.send(.continueButtonTapped) {
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000123"
    }
    await store.receive(.hostValidationSucceeded) {
      $0.step = .repository
      $0.validationMessage = nil
    }

    #expect(savedPasswords.snapshot()["00000000-0000-0000-0000-000000000123"] == "secret")
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
    let commands = StringArrayRecorder()
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 3))
      $0.uuid = .incrementing
      $0.remoteExecutionClient.run = { _, command, _ in
        commands.append(command)
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

    let rootRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let childRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    await store.send(.browseRemoteFoldersButtonTapped) {
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000000"
      $0.activeBrowseRequestID = rootRequestID
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "",
        childDirectories: [],
        isLoading: true,
        errorMessage: nil
      )
    }
    await store.receive(
      .remoteDirectoryListingLoaded(
        rootRequestID,
        RemoteConnectFeature.DirectoryListing(
          currentPath: "/Users/deploy",
          childDirectories: [
            "/Users/deploy/src",
            "/Users/deploy/work",
          ]
        )
      )
    ) {
      $0.activeBrowseRequestID = nil
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
      $0.activeBrowseRequestID = childRequestID
      $0.directoryBrowser?.isLoading = true
      $0.directoryBrowser?.errorMessage = nil
    }
    await store.receive(
      .remoteDirectoryListingLoaded(
        childRequestID,
        RemoteConnectFeature.DirectoryListing(
          currentPath: "/Users/deploy/src",
          childDirectories: [
            "/Users/deploy/src/project"
          ]
        )
      )
    ) {
      $0.activeBrowseRequestID = nil
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
      $0.activeBrowseRequestID = nil
    }

    let recordedCommands = commands.snapshot()
    #expect(recordedCommands.count == 2)
  }

  @Test func browseRemoteFoldersRequiresPasswordWhenPasswordAuthIsSelected() async {
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"
    state.authMethod = .password

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 4))
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
      $0.keychainClient = .testValue
    }

    await store.send(.browseRemoteFoldersButtonTapped) {
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000000"
      $0.activeBrowseRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "",
        childDirectories: [],
        isLoading: true,
        errorMessage: nil
      )
    }
    await store.receive(.hostValidationFailed("Password required.")) {
      $0.validationMessage = "Password required."
      $0.activeBrowseRequestID = nil
      $0.directoryBrowser?.isLoading = false
      $0.directoryBrowser?.errorMessage = "Password required."
    }
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

  @Test func repeatedConnectButtonTapWhileSubmittingIsIgnored() async {
    let gate = AsyncGate()
    let runCount = IntRecorder()
    let now = Date(timeIntervalSince1970: 30)
    let newProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!.uuidString
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"
    state.remotePath = "/srv/repo"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.uuid = .constant(UUID(uuidString: newProfileID)!)
      $0.remoteExecutionClient.run = { _, _, _ in
        runCount.increment()
        await gate.wait()
        return RemoteExecutionClient.Output(
          stdout: "/srv/repo\n",
          stderr: "",
          exitCode: 0
        )
      }
    }

    await store.send(.connectButtonTapped) {
      $0.isSubmitting = true
      $0.validationMessage = nil
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000000"
    }
    await store.send(.connectButtonTapped)

    #expect(runCount.snapshot() == 1)

    await gate.resume()

    let expectedSubmission = RemoteConnectFeature.Submission(
      hostProfile: SSHHostProfile(
        id: newProfileID,
        displayName: "example.com",
        host: "example.com",
        user: "deploy",
        authMethod: .publicKey,
        createdAt: now,
        updatedAt: now
      ),
      remotePath: "/srv/repo"
    )

    await store.receive(.remoteRepositoryValidated(expectedSubmission)) {
      $0.remotePath = "/srv/repo"
      $0.isSubmitting = false
    }
    await store.receive(.delegate(.completed(expectedSubmission)))
  }

  @Test func staleBrowseResponseIsIgnoredAfterDismiss() async {
    let staleRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let activeRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"
    state.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
      currentPath: "/Users/deploy",
      childDirectories: [],
      isLoading: true,
      errorMessage: nil
    )
    state.activeBrowseRequestID = staleRequestID

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    }

    await store.send(.directoryBrowserDismissed) {
      $0.directoryBrowser = nil
      $0.activeBrowseRequestID = nil
    }
    await store.send(
      .remoteDirectoryListingLoaded(
        activeRequestID,
        RemoteConnectFeature.DirectoryListing(
          currentPath: "/tmp",
          childDirectories: ["/tmp/repo"]
        )
      )
    )
  }

  @Test func staleBrowseResponseIsIgnoredAfterBack() async {
    let activeRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"
    state.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
      currentPath: "/Users/deploy",
      childDirectories: [],
      isLoading: true,
      errorMessage: nil
    )
    state.activeBrowseRequestID = activeRequestID

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    }

    await store.send(.backButtonTapped) {
      $0.step = .host
      $0.directoryBrowser = nil
      $0.activeBrowseRequestID = nil
      $0.validationMessage = nil
    }
    await store.send(
      .remoteDirectoryListingFailed(
        activeRequestID,
        "Couldn't browse remote folders."
      )
    )
  }

  @Test func browseRemoteFoldersFailureMapsMissingDirectoryToFriendlyMessage() async {
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 5))
      $0.uuid = .incrementing
      $0.remoteExecutionClient.run = { _, _, _ in
        RemoteExecutionClient.Output(
          stdout: "",
          stderr: "__PROWL_REMOTE_CONNECT__:missing-directory\n",
          exitCode: 20
        )
      }
    }

    let connectionProfileID = "00000000-0000-0000-0000-000000000000"
    let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    await store.send(.browseRemoteFoldersButtonTapped) {
      $0.connectionHostProfileID = connectionProfileID
      $0.activeBrowseRequestID = requestID
      $0.directoryBrowser = RemoteConnectFeature.DirectoryBrowserState(
        currentPath: "",
        childDirectories: [],
        isLoading: true,
        errorMessage: nil
      )
    }
    await store.receive(
      .remoteDirectoryListingFailed(
        requestID,
        "The remote folder couldn't be opened."
      )
    ) {
      $0.activeBrowseRequestID = nil
      $0.directoryBrowser?.isLoading = false
      $0.directoryBrowser?.errorMessage = "The remote folder couldn't be opened."
    }
  }

  @Test func connectValidationFailureMapsNotGitToFriendlyMessage() async {
    var state = RemoteConnectFeature.State(savedHostProfiles: [])
    state.step = .repository
    state.host = "example.com"
    state.user = "deploy"
    state.remotePath = "/srv/not-a-repo"

    let store = TestStore(initialState: state) {
      RemoteConnectFeature()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 40))
      $0.uuid = .incrementing
      $0.remoteExecutionClient.run = { _, _, _ in
        RemoteExecutionClient.Output(
          stdout: "",
          stderr: "__PROWL_REMOTE_CONNECT__:not-git\n",
          exitCode: 21
        )
      }
    }

    await store.send(.connectButtonTapped) {
      $0.isSubmitting = true
      $0.validationMessage = nil
      $0.connectionHostProfileID = "00000000-0000-0000-0000-000000000000"
    }
    await store.receive(
      .remoteRepositoryValidationFailed("The selected folder is not a Git repository.")
    ) {
      $0.isSubmitting = false
      $0.validationMessage = "The selected folder is not a Git repository."
    }
  }
}

private actor AsyncGate {
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}
