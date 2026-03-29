import ComposableArchitecture
import Foundation

@Reducer
struct SSHHostsFeature {
  @ObservableState
  struct State: Equatable {
    var hosts: [SSHHostProfile] = []
    var selectedHostID: SSHHostProfile.ID?
    var displayName = ""
    var host = ""
    var user = ""
    var port = ""
    var authMethod: SSHHostProfile.AuthMethod = .publicKey
    var isCreating = false
    var validationMessage: String?
    @Presents var alert: AlertState<Alert>?
  }

  enum Action: BindableAction {
    case task
    case hostSelected(SSHHostProfile.ID?)
    case addHostTapped
    case deleteHostTapped
    case saveButtonTapped
    case alert(PresentationAction<Alert>)
    case binding(BindingAction<State>)
  }

  enum Alert: Equatable {
    case confirmDelete(SSHHostProfile.ID)
  }

  @Dependency(\.date) private var date
  @Dependency(\.uuid) private var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        @Shared(.settingsFile) var settingsFile
        loadHosts(settingsFile.sshHostProfiles, into: &state)
        return .none

      case .hostSelected(let hostID):
        state.validationMessage = nil
        state.alert = nil
        guard let hostID, let profile = state.hosts.first(where: { $0.id == hostID }) else {
          clearEditorFields(in: &state)
          return .none
        }
        state.selectedHostID = hostID
        state.isCreating = false
        setEditorFields(from: profile, in: &state)
        return .none

      case .addHostTapped:
        state.selectedHostID = nil
        state.isCreating = true
        state.validationMessage = nil
        state.alert = nil
        state.displayName = ""
        state.host = ""
        state.user = ""
        state.port = ""
        state.authMethod = .publicKey
        return .none

      case .deleteHostTapped:
        guard let hostID = state.selectedHostID else {
          return .none
        }
        let boundCount = remoteBindingCount(for: hostID)
        guard boundCount == 0 else {
          state.validationMessage =
            boundCount == 1
            ? "This host is used by 1 remote repository and cannot be deleted."
            : "This host is used by \(boundCount) remote repositories and cannot be deleted."
          return .none
        }
        guard let profile = state.hosts.first(where: { $0.id == hostID }) else {
          return .none
        }
        state.alert = deleteConfirmationAlert(for: profile)
        return .none

      case .saveButtonTapped:
        guard let normalizedHost = normalizedHost(in: &state) else {
          return .none
        }
        guard let normalizedPort = normalizedPort(in: &state) else {
          return .none
        }
        state.validationMessage = nil
        let normalizedDisplayName =
          state.displayName
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = normalizedDisplayName.isEmpty ? normalizedHost : normalizedDisplayName
        let normalizedUser = state.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = date.now

        if state.isCreating || state.selectedHostID == nil {
          let profile = SSHHostProfile(
            id: uuid().uuidString,
            displayName: resolvedDisplayName,
            host: normalizedHost,
            user: normalizedUser,
            port: normalizedPort,
            authMethod: state.authMethod,
            createdAt: now,
            updatedAt: now
          )
          state.hosts.append(profile)
          state.hosts = sortProfiles(state.hosts)
          state.selectedHostID = profile.id
          state.isCreating = false
        } else if let selectedHostID = state.selectedHostID,
          let index = state.hosts.firstIndex(where: { $0.id == selectedHostID })
        {
          let existing = state.hosts[index]
          state.hosts[index] = SSHHostProfile(
            id: existing.id,
            displayName: resolvedDisplayName,
            host: normalizedHost,
            user: normalizedUser,
            port: normalizedPort,
            authMethod: state.authMethod,
            createdAt: existing.createdAt,
            updatedAt: now
          )
          state.hosts = sortProfiles(state.hosts)
        }

        if let selectedHostID = state.selectedHostID,
          let profile = state.hosts.first(where: { $0.id == selectedHostID })
        {
          setEditorFields(from: profile, in: &state)
        }
        persistHosts(state.hosts)
        return .none

      case .binding:
        state.validationMessage = nil
        return .none

      case .alert(.presented(.confirmDelete(let hostID))):
        state.alert = nil
        guard let index = state.hosts.firstIndex(where: { $0.id == hostID }) else {
          return .none
        }
        state.hosts.remove(at: index)
        state.hosts = sortProfiles(state.hosts)
        state.validationMessage = nil
        persistHosts(state.hosts)

        guard !state.hosts.isEmpty else {
          clearEditorFields(in: &state)
          return .none
        }
        let nextIndex = min(index, state.hosts.count - 1)
        let nextProfile = state.hosts[nextIndex]
        state.selectedHostID = nextProfile.id
        state.isCreating = false
        setEditorFields(from: nextProfile, in: &state)
        return .none

      case .alert:
        state.alert = nil
        return .none
      }
    }
  }

  private func loadHosts(_ hosts: [SSHHostProfile], into state: inout State) {
    state.hosts = sortProfiles(hosts)
    if let selectedHostID = state.selectedHostID,
      let selected = state.hosts.first(where: { $0.id == selectedHostID })
    {
      state.isCreating = false
      setEditorFields(from: selected, in: &state)
      return
    }
    guard let first = state.hosts.first else {
      clearEditorFields(in: &state)
      return
    }
    state.selectedHostID = first.id
    state.isCreating = false
    setEditorFields(from: first, in: &state)
  }

  private func persistHosts(_ hosts: [SSHHostProfile]) {
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock {
      $0.sshHostProfiles = sortProfiles(hosts)
    }
  }

  private func sortProfiles(_ hosts: [SSHHostProfile]) -> [SSHHostProfile] {
    hosts.sorted { lhs, rhs in
      let displayNameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
      if displayNameOrder == .orderedSame {
        return lhs.host.localizedStandardCompare(rhs.host) == .orderedAscending
      }
      return displayNameOrder == .orderedAscending
    }
  }

  private func clearEditorFields(in state: inout State) {
    state.selectedHostID = nil
    state.isCreating = false
    state.displayName = ""
    state.host = ""
    state.user = ""
    state.port = ""
    state.authMethod = .publicKey
    state.validationMessage = nil
  }

  private func setEditorFields(from profile: SSHHostProfile, in state: inout State) {
    state.displayName = profile.displayName
    state.host = profile.host
    state.user = profile.user
    state.port = profile.port.map(String.init) ?? ""
    state.authMethod = profile.authMethod
  }

  private func normalizedHost(in state: inout State) -> String? {
    let host = state.host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
      state.validationMessage = "Host required."
      return nil
    }
    return host
  }

  private func normalizedPort(in state: inout State) -> Int? {
    let port = state.port.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !port.isEmpty else {
      return nil
    }
    guard let parsed = Int(port), (1 ... 65_535).contains(parsed) else {
      state.validationMessage = "Port must be between 1 and 65535."
      return nil
    }
    return parsed
  }

  private func remoteBindingCount(for hostID: SSHHostProfile.ID) -> Int {
    @Shared(.repositoryEntries) var repositoryEntries
    return repositoryEntries.reduce(into: 0) { count, entry in
      if case .remote(let boundHostID, _) = entry.endpoint, boundHostID == hostID {
        count += 1
      }
    }
  }

  private func deleteConfirmationAlert(for profile: SSHHostProfile) -> AlertState<Alert> {
    AlertState {
      TextState("Delete SSH host?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete(profile.id)) {
        TextState("Delete")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Delete \(profile.displayName)? Remote repositories using this host stay configured.")
    }
  }
}
