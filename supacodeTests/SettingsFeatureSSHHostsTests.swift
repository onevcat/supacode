import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct SettingsFeatureSSHHostsTests {
  @Test func addHostAppendsProfile() async throws {
    let storage = SettingsTestStorage()
    let testID = UUID().uuidString
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(testID).json")
    let repositoryEntriesFileURL = URL(fileURLWithPath: "/tmp/supacode-repositories-\(testID).json")
    let hostID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let now = Date(timeIntervalSince1970: 100)

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryEntriesFileURL = repositoryEntriesFileURL
      $0.uuid = .constant(hostID)
      $0.date = .constant(now)
    } operation: {
      @Shared(.repositoryEntries) var repositoryEntries: [PersistedRepositoryEntry]
      $repositoryEntries.withLock {
        $0 = []
      }
      return TestStore(initialState: SSHHostsFeature.State()) {
        SSHHostsFeature()
      }
    }

    await store.send(.task)
    await store.send(.addHostTapped) {
      $0.isCreating = true
    }
    await store.send(.binding(.set(\.displayName, "Build Box"))) {
      $0.displayName = "Build Box"
    }
    await store.send(.binding(.set(\.host, "example.com"))) {
      $0.host = "example.com"
    }
    await store.send(.binding(.set(\.user, "deploy"))) {
      $0.user = "deploy"
    }
    await store.send(.binding(.set(\.port, "2222"))) {
      $0.port = "2222"
    }
    await store.send(.binding(.set(\.authMethod, .password))) {
      $0.authMethod = .password
    }

    let expectedProfile = SSHHostProfile(
      id: hostID.uuidString,
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      port: 2222,
      authMethod: .password,
      createdAt: now,
      updatedAt: now
    )

    await store.send(.saveButtonTapped) {
      $0.hosts = [expectedProfile]
      $0.selectedHostID = expectedProfile.id
      $0.isCreating = false
      $0.displayName = "Build Box"
      $0.host = "example.com"
      $0.user = "deploy"
      $0.port = "2222"
      $0.authMethod = .password
      $0.validationMessage = nil
    }

    let persisted = try decodeSettingsFile(storage: storage, url: settingsFileURL)
    #expect(persisted.sshHostProfiles == [expectedProfile])
  }

  @Test func updateHostPersistsEditedFields() async throws {
    let storage = SettingsTestStorage()
    let testID = UUID().uuidString
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(testID).json")
    let repositoryEntriesFileURL = URL(fileURLWithPath: "/tmp/supacode-repositories-\(testID).json")
    let createdAt = Date(timeIntervalSince1970: 10)
    let updatedAt = Date(timeIntervalSince1970: 20)
    let initial = SSHHostProfile(
      id: "host-1",
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      port: 22,
      authMethod: .publicKey,
      createdAt: createdAt,
      updatedAt: createdAt
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryEntriesFileURL = repositoryEntriesFileURL
      $0.date = .constant(updatedAt)
    } operation: {
      @Shared(.settingsFile) var settingsFile
      $settingsFile.withLock {
        $0.sshHostProfiles = [initial]
      }
      @Shared(.repositoryEntries) var repositoryEntries: [PersistedRepositoryEntry]
      $repositoryEntries.withLock {
        $0 = []
      }
      return TestStore(initialState: SSHHostsFeature.State()) {
        SSHHostsFeature()
      }
    }

    await store.send(.task) {
      $0.hosts = [initial]
      $0.selectedHostID = initial.id
      $0.displayName = "Build Box"
      $0.host = "example.com"
      $0.user = "deploy"
      $0.port = "22"
      $0.authMethod = .publicKey
      $0.isCreating = false
    }
    await store.send(.binding(.set(\.displayName, "Build Box Updated"))) {
      $0.displayName = "Build Box Updated"
    }
    await store.send(.binding(.set(\.port, "2202"))) {
      $0.port = "2202"
    }

    let expected = SSHHostProfile(
      id: initial.id,
      displayName: "Build Box Updated",
      host: "example.com",
      user: "deploy",
      port: 2202,
      authMethod: .publicKey,
      createdAt: createdAt,
      updatedAt: updatedAt
    )

    await store.send(.saveButtonTapped) {
      $0.hosts = [expected]
      $0.selectedHostID = expected.id
      $0.displayName = "Build Box Updated"
      $0.host = "example.com"
      $0.user = "deploy"
      $0.port = "2202"
      $0.authMethod = .publicKey
      $0.validationMessage = nil
    }

    let persisted = try decodeSettingsFile(storage: storage, url: settingsFileURL)
    #expect(persisted.sshHostProfiles == [expected])
  }

  @Test func deleteHostFailsWhenBoundRepositoriesExist() async throws {
    let storage = SettingsTestStorage()
    let testID = UUID().uuidString
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(testID).json")
    let repositoryEntriesFileURL = URL(fileURLWithPath: "/tmp/supacode-repositories-\(testID).json")
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      authMethod: .publicKey
    )
    let boundEntry = PersistedRepositoryEntry(
      path: "/srv/repo",
      kind: .git,
      endpoint: .remote(hostProfileID: profile.id, remotePath: "/srv/repo")
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryEntriesFileURL = repositoryEntriesFileURL
    } operation: {
      @Shared(.settingsFile) var settingsFile
      $settingsFile.withLock {
        $0.sshHostProfiles = [profile]
      }
      @Shared(.repositoryEntries) var repositoryEntries: [PersistedRepositoryEntry]
      $repositoryEntries.withLock {
        $0 = [boundEntry]
      }
      return TestStore(initialState: SSHHostsFeature.State()) {
        SSHHostsFeature()
      }
    }

    await store.send(.task) {
      $0.hosts = [profile]
      $0.selectedHostID = profile.id
      $0.displayName = "Build Box"
      $0.host = "example.com"
      $0.user = "deploy"
      $0.port = ""
      $0.authMethod = .publicKey
    }
    await store.send(.deleteHostTapped) {
      $0.validationMessage = "This host is used by 1 remote repository and cannot be deleted."
    }

    #expect(store.state.hosts == [profile])
    let persisted = try decodeSettingsFile(storage: storage, url: settingsFileURL)
    #expect(persisted.sshHostProfiles == [profile])
  }

  @Test func deleteHostRemovesUnboundProfileAfterConfirmation() async throws {
    let storage = SettingsTestStorage()
    let testID = UUID().uuidString
    let settingsFileURL = URL(fileURLWithPath: "/tmp/supacode-settings-\(testID).json")
    let repositoryEntriesFileURL = URL(fileURLWithPath: "/tmp/supacode-repositories-\(testID).json")
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "Build Box",
      host: "example.com",
      user: "deploy",
      authMethod: .publicKey
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
      $0.repositoryEntriesFileURL = repositoryEntriesFileURL
    } operation: {
      @Shared(.settingsFile) var settingsFile
      $settingsFile.withLock {
        $0.sshHostProfiles = [profile]
      }
      @Shared(.repositoryEntries) var repositoryEntries: [PersistedRepositoryEntry]
      $repositoryEntries.withLock {
        $0 = []
      }
      return TestStore(initialState: SSHHostsFeature.State()) {
        SSHHostsFeature()
      }
    }

    await store.send(.task) {
      $0.hosts = [profile]
      $0.selectedHostID = profile.id
      $0.displayName = "Build Box"
      $0.host = "example.com"
      $0.user = "deploy"
      $0.port = ""
      $0.authMethod = .publicKey
    }
    await store.send(.alert(.presented(.confirmDelete(profile.id)))) {
      $0.hosts = []
      $0.selectedHostID = nil
      $0.displayName = ""
      $0.host = ""
      $0.user = ""
      $0.port = ""
      $0.authMethod = .publicKey
      $0.isCreating = false
      $0.validationMessage = nil
      $0.alert = nil
    }

    let persisted = try decodeSettingsFile(storage: storage, url: settingsFileURL)
    #expect(persisted.sshHostProfiles.isEmpty)
  }

  private func decodeSettingsFile(
    storage: SettingsTestStorage,
    url: URL
  ) throws -> SettingsFile {
    let data = try storage.storage.load(url)
    return try JSONDecoder().decode(SettingsFile.self, from: data)
  }
}
