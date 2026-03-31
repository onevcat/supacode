import ComposableArchitecture
import Foundation

private enum CancelID {
  static let browseDirectoryListing = "remote-connect.browse-directory-listing"
}

@Reducer
struct RemoteConnectFeature {
  enum Step: Equatable {
    case host
    case repository
  }

  struct DirectoryListing: Equatable, Sendable {
    let currentPath: String
    let childDirectories: [String]
  }

  struct DirectoryBrowserState: Equatable {
    var currentPath: String
    var childDirectories: [String]
    var isLoading: Bool
    var errorMessage: String?
  }

  struct Submission: Equatable, Sendable {
    let hostProfile: SSHHostProfile
    let remotePath: String
  }

  @ObservableState
  struct State: Equatable {
    var savedHostProfiles: [SSHHostProfile]
    var selectedHostProfileID: SSHHostProfile.ID?
    var connectionHostProfileID: SSHHostProfile.ID?
    var connectionHostProfileEndpointKey: String?
    var step: Step = .host
    var displayName = ""
    var host = ""
    var user = ""
    var port = ""
    var authMethod: SSHHostProfile.AuthMethod = .publicKey
    var password = ""
    var remotePath = ""
    var validationMessage: String?
    var isSubmitting = false
    var directoryBrowser: DirectoryBrowserState?
    var activeBrowseRequestID: UUID?

    init(savedHostProfiles: [SSHHostProfile]) {
      self.savedHostProfiles = savedHostProfiles.sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
    }

    var selectedHostProfile: SSHHostProfile? {
      guard let selectedHostProfileID else {
        return nil
      }
      return savedHostProfiles.first { $0.id == selectedHostProfileID }
    }

    var resolvedDisplayName: String {
      let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
      return host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case savedHostProfileSelected(SSHHostProfile.ID?)
    case continueButtonTapped
    case backButtonTapped
    case cancelButtonTapped
    case browseRemoteFoldersButtonTapped
    case remoteDirectoryListingLoaded(UUID, DirectoryListing)
    case remoteDirectoryListingFailed(UUID, String)
    case directoryBrowserEntryTapped(String)
    case directoryBrowserUpButtonTapped
    case directoryBrowserChooseCurrentFolderButtonTapped
    case directoryBrowserDismissed
    case connectButtonTapped
    case hostValidationSucceeded
    case hostValidationFailed(String)
    case remoteRepositoryValidated(Submission)
    case remoteRepositoryValidationFailed(String)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case cancel
    case completed(Submission)
  }

  @Dependency(\.date.now) private var now
  @Dependency(KeychainClient.self) private var keychainClient
  @Dependency(RemoteExecutionClient.self) private var remoteExecutionClient
  @Dependency(\.uuid) private var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.validationMessage = nil
        return .none

      case .savedHostProfileSelected(let profileID):
        state.selectedHostProfileID = profileID
        state.connectionHostProfileID = nil
        state.connectionHostProfileEndpointKey = nil
        state.password = ""
        state.validationMessage = nil
        guard let profile = state.savedHostProfiles.first(where: { $0.id == profileID }) else {
          state.displayName = ""
          state.host = ""
          state.user = ""
          state.port = ""
          state.authMethod = .publicKey
          return .none
        }
        state.displayName = profile.displayName
        state.host = profile.host
        state.user = profile.user
        state.port = profile.port.map(String.init) ?? ""
        state.authMethod = profile.authMethod
        return .none

      case .continueButtonTapped:
        guard let hostFields = validateHostFields(in: &state) else {
          return .none
        }
        let profileID = resolvedHostProfileID(in: &state, hostFields: hostFields)
        let existingProfile = matchingSavedHostProfile(in: state, hostFields: hostFields)
        let keychain = keychainClient
        if state.authMethod == .password {
          let hostProfile = makeConnectionProfile(
            from: hostFields,
            existingProfile: existingProfile,
            profileID: profileID,
            now: now
          )
          let password = state.password
          return .run { send in
            do {
              if !password.isEmpty {
                try await keychain.savePassword(password, hostProfile.id)
              } else if try await keychain.loadPassword(hostProfile.id) == nil {
                await send(.hostValidationFailed("Password required."))
                return
              }
              await send(.hostValidationSucceeded)
            } catch {
              await send(
                .hostValidationFailed(
                  genericFailureMessage(
                    prefix: "Couldn't validate the SSH host.",
                    detail: error.localizedDescription
                  )
                )
              )
            }
          }
        }
        state.step = .repository
        return .none

      case .backButtonTapped:
        state.step = .host
        clearBrowseState(in: &state)
        state.validationMessage = nil
        return .cancel(id: CancelID.browseDirectoryListing)

      case .cancelButtonTapped:
        return .send(.delegate(.cancel))

      case .browseRemoteFoldersButtonTapped:
        guard let hostFields = validateHostFields(in: &state) else {
          return .none
        }
        let requestedPathResult = requestedPath(
          from: state.remotePath,
          allowEmptyAsHome: true
        )
        guard case .success(let requestedPath) = requestedPathResult else {
          if case .failure(let message) = requestedPathResult {
            state.validationMessage = message
          }
          return .none
        }

        let profileID = resolvedHostProfileID(in: &state, hostFields: hostFields)
        let existingProfile = matchingSavedHostProfile(in: state, hostFields: hostFields)
        let profile = makeConnectionProfile(
          from: hostFields,
          existingProfile: existingProfile,
          profileID: profileID,
          now: now
        )
        let keychain = keychainClient
        let requestID = uuid()
        state.validationMessage = nil
        state.activeBrowseRequestID = requestID
        state.directoryBrowser = DirectoryBrowserState(
          currentPath: state.remotePath.trimmingCharacters(in: .whitespacesAndNewlines),
          childDirectories: [],
          isLoading: true,
          errorMessage: nil
        )
        return browseDirectoryEffect(
          requestID: requestID,
          profile: profile,
          requestedPath: requestedPath,
          password: state.password,
          keychainClient: keychain
        )

      case .remoteDirectoryListingLoaded(let requestID, let listing):
        guard state.activeBrowseRequestID == requestID, state.directoryBrowser != nil else {
          return .none
        }
        state.activeBrowseRequestID = nil
        state.directoryBrowser = DirectoryBrowserState(
          currentPath: listing.currentPath,
          childDirectories: listing.childDirectories,
          isLoading: false,
          errorMessage: nil
        )
        return .none

      case .remoteDirectoryListingFailed(let requestID, let message):
        guard state.activeBrowseRequestID == requestID else {
          return .none
        }
        state.activeBrowseRequestID = nil
        if state.directoryBrowser != nil {
          state.directoryBrowser?.isLoading = false
          state.directoryBrowser?.errorMessage = message
        } else {
          state.validationMessage = message
        }
        return .none

      case .directoryBrowserEntryTapped(let path):
        guard let directoryBrowser = state.directoryBrowser else {
          return .none
        }
        state.directoryBrowser?.isLoading = true
        state.directoryBrowser?.errorMessage = nil
        guard let hostFields = validateHostFields(in: &state) else {
          state.directoryBrowser = directoryBrowser
          return .none
        }
        let profileID = resolvedHostProfileID(in: &state, hostFields: hostFields)
        let existingProfile = matchingSavedHostProfile(in: state, hostFields: hostFields)
        let profile = makeConnectionProfile(
          from: hostFields,
          existingProfile: existingProfile,
          profileID: profileID,
          now: now
        )
        let keychain = keychainClient
        let requestID = uuid()
        state.activeBrowseRequestID = requestID
        return browseDirectoryEffect(
          requestID: requestID,
          profile: profile,
          requestedPath: .absolute(path),
          password: state.password,
          keychainClient: keychain
        )

      case .directoryBrowserUpButtonTapped:
        guard let directoryBrowser = state.directoryBrowser else {
          return .none
        }
        let parentPath = Self.parentDirectory(of: directoryBrowser.currentPath)
        guard parentPath != directoryBrowser.currentPath else {
          return .none
        }
        return .send(.directoryBrowserEntryTapped(parentPath))

      case .directoryBrowserChooseCurrentFolderButtonTapped:
        guard let currentPath = state.directoryBrowser?.currentPath, !currentPath.isEmpty else {
          return .none
        }
        state.remotePath = currentPath
        clearBrowseState(in: &state)
        return .cancel(id: CancelID.browseDirectoryListing)

      case .directoryBrowserDismissed:
        clearBrowseState(in: &state)
        return .cancel(id: CancelID.browseDirectoryListing)

      case .connectButtonTapped:
        guard !state.isSubmitting else {
          return .none
        }
        guard let hostFields = validateHostFields(in: &state) else {
          return .none
        }
        let requestedPathResult = requestedPath(
          from: state.remotePath,
          allowEmptyAsHome: false
        )
        guard case .success(let requestedPath) = requestedPathResult else {
          if case .failure(let message) = requestedPathResult {
            state.validationMessage = message
          }
          return .none
        }

        let profileID = resolvedHostProfileID(in: &state, hostFields: hostFields)
        let existingProfile = matchingSavedHostProfile(in: state, hostFields: hostFields)
        let submissionProfile = makeSubmissionProfile(
          from: hostFields,
          existingProfile: existingProfile,
          profileID: profileID,
          now: now
        )
        let keychain = keychainClient
        state.validationMessage = nil
        state.isSubmitting = true
        let password = state.password
        return .run { send in
          do {
            if submissionProfile.authMethod == .password {
              if !password.isEmpty {
                try await keychain.savePassword(password, submissionProfile.id)
              } else if try await keychain.loadPassword(submissionProfile.id) == nil {
                await send(.hostValidationFailed("Password required."))
                return
              }
            }
            let output = try await remoteExecutionClient.run(
              submissionProfile,
              validateRepositoryCommand(for: requestedPath),
              remoteCommandTimeoutSeconds
            )
            guard output.exitCode == 0 else {
              await send(
                .remoteRepositoryValidationFailed(
                  repositoryValidationFailureMessage(for: output)
                )
              )
              return
            }
            let normalizedPath = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPath.isEmpty else {
              await send(.remoteRepositoryValidationFailed("Couldn't validate the remote repository."))
              return
            }
            await send(
              .remoteRepositoryValidated(
                Submission(
                  hostProfile: submissionProfile,
                  remotePath: normalizedPath
                )
              )
            )
          } catch {
            await send(
              .remoteRepositoryValidationFailed(
                genericFailureMessage(
                  prefix: "Couldn't validate the remote repository.",
                  detail: error.localizedDescription
                )
              )
            )
          }
        }

      case .hostValidationSucceeded:
        state.validationMessage = nil
        state.step = .repository
        return .none

      case .hostValidationFailed(let message):
        state.isSubmitting = false
        state.validationMessage = message
        if state.directoryBrowser != nil {
          state.activeBrowseRequestID = nil
          state.directoryBrowser?.isLoading = false
          state.directoryBrowser?.errorMessage = message
        }
        return .none

      case .remoteRepositoryValidated(let submission):
        state.isSubmitting = false
        state.remotePath = submission.remotePath
        return .send(.delegate(.completed(submission)))

      case .remoteRepositoryValidationFailed(let message):
        state.isSubmitting = false
        state.validationMessage = message
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func browseDirectoryEffect(
    requestID: UUID,
    profile: SSHHostProfile,
    requestedPath: RemotePathRequest,
    password: String,
    keychainClient: KeychainClient
  ) -> Effect<Action> {
    .run { send in
      do {
        if profile.authMethod == .password {
          if !password.isEmpty {
            try await keychainClient.savePassword(password, profile.id)
          } else if try await keychainClient.loadPassword(profile.id) == nil {
            await send(.hostValidationFailed("Password required."))
            return
          }
        }
        let output = try await remoteExecutionClient.run(
          profile,
          listDirectoriesCommand(for: requestedPath),
          remoteCommandTimeoutSeconds
        )
        guard output.exitCode == 0 else {
          await send(
            .remoteDirectoryListingFailed(
              requestID,
              directoryListingFailureMessage(for: output)
            )
          )
          return
        }
        let lines = output.stdout
          .split(whereSeparator: \.isNewline)
          .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        guard let currentPath = lines.first else {
          await send(.remoteDirectoryListingFailed(requestID, "Couldn't load remote folders."))
          return
        }
        let childDirectories = Array(lines.dropFirst())
        await send(
          .remoteDirectoryListingLoaded(
            requestID,
            DirectoryListing(
              currentPath: currentPath,
              childDirectories: childDirectories
            )
          )
        )
      } catch {
        guard !(error is CancellationError) else {
          return
        }
        await send(
          .remoteDirectoryListingFailed(
            requestID,
            genericFailureMessage(
              prefix: "Couldn't browse remote folders.",
              detail: error.localizedDescription
            )
          )
        )
      }
    }
    .cancellable(id: CancelID.browseDirectoryListing, cancelInFlight: true)
  }

  private func clearBrowseState(in state: inout State) {
    state.directoryBrowser = nil
    state.activeBrowseRequestID = nil
  }

  private func validateHostFields(in state: inout State) -> HostFields? {
    let host = state.host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
      state.validationMessage = "Host required."
      return nil
    }

    let user = state.user.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let portValue = state.port.trimmingCharacters(in: .whitespacesAndNewlines)
    let port: Int?
    if portValue.isEmpty {
      port = nil
    } else if let parsed = Int(portValue), (1 ... 65535).contains(parsed) {
      port = parsed
    } else {
      state.validationMessage = "Enter a valid SSH port."
      return nil
    }

    return HostFields(
      displayName: displayName.isEmpty ? host : displayName,
      host: host,
      user: user,
      port: port,
      authMethod: state.authMethod
    )
  }

  private func resolvedHostProfileID(
    in state: inout State,
    hostFields: HostFields
  ) -> SSHHostProfile.ID {
    if let selectedHostProfile = matchingSavedHostProfile(in: state, hostFields: hostFields) {
      state.connectionHostProfileID = nil
      state.connectionHostProfileEndpointKey = nil
      return selectedHostProfile.id
    }

    let endpointKey = connectionHostProfileEndpointKey(for: hostFields)
    if state.connectionHostProfileEndpointKey == endpointKey,
      let connectionHostProfileID = state.connectionHostProfileID
    {
      return connectionHostProfileID
    }

    let connectionHostProfileID = uuid().uuidString
    state.connectionHostProfileID = connectionHostProfileID
    state.connectionHostProfileEndpointKey = endpointKey
    return connectionHostProfileID
  }

  private func matchingSavedHostProfile(
    in state: State,
    hostFields: HostFields
  ) -> SSHHostProfile? {
    guard let selectedHostProfile = state.selectedHostProfile else {
      return nil
    }
    guard selectedHostProfile.host == hostFields.host,
      selectedHostProfile.user == hostFields.user,
      selectedHostProfile.port == hostFields.port
    else {
      return nil
    }
    return selectedHostProfile
  }

  private func connectionHostProfileEndpointKey(for hostFields: HostFields) -> String {
    [
      hostFields.host,
      hostFields.user,
      hostFields.port.map(String.init) ?? "",
    ]
    .joined(separator: "|")
  }

  private func makeConnectionProfile(
    from hostFields: HostFields,
    existingProfile: SSHHostProfile?,
    profileID: SSHHostProfile.ID,
    now: Date
  ) -> SSHHostProfile {
    SSHHostProfile(
      id: existingProfile?.id ?? profileID,
      displayName: hostFields.displayName,
      host: hostFields.host,
      user: hostFields.user,
      port: hostFields.port,
      authMethod: hostFields.authMethod,
      createdAt: existingProfile?.createdAt ?? now,
      updatedAt: now
    )
  }

  private func makeSubmissionProfile(
    from hostFields: HostFields,
    existingProfile: SSHHostProfile?,
    profileID: SSHHostProfile.ID,
    now: Date
  ) -> SSHHostProfile {
    makeConnectionProfile(
      from: hostFields,
      existingProfile: existingProfile,
      profileID: profileID,
      now: now
    )
  }

  private func requestedPath(
    from rawValue: String,
    allowEmptyAsHome: Bool
  ) -> RequestedPathResult {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return allowEmptyAsHome ? .success(.home) : .failure("Remote path required.")
    }
    if trimmed == "~" {
      return .success(.home)
    }
    if trimmed.hasPrefix("~/") {
      return .success(.homeRelative(String(trimmed.dropFirst(2))))
    }
    if trimmed.hasPrefix("/") {
      return .success(.absolute(trimmed))
    }
    return .failure("Enter an absolute remote path or browse remote folders.")
  }

  private func listDirectoriesCommand(for requestedPath: RemotePathRequest) -> String {
    let pathAssignment = pathAssignment(for: requestedPath)
    return """
      \(pathAssignment)
      if ! cd -- "$remote_base" 2>/dev/null; then
        printf '%s\\n' '\(errorMarker)missing-directory' >&2
        exit 20
      fi
      current=$(pwd -P)
      printf '%s\\n' "$current"
      find "$current" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | LC_ALL=C sort
      """
  }

  private func validateRepositoryCommand(for requestedPath: RemotePathRequest) -> String {
    let pathAssignment = pathAssignment(for: requestedPath)
    return """
      \(pathAssignment)
      if ! cd -- "$remote_base" 2>/dev/null; then
        printf '%s\\n' '\(errorMarker)missing-directory' >&2
        exit 20
      fi
      repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
      if [ -z "$repo_root" ]; then
        printf '%s\\n' '\(errorMarker)not-git' >&2
        exit 21
      fi
      printf '%s\\n' "$repo_root"
      """
  }

  private func pathAssignment(for requestedPath: RemotePathRequest) -> String {
    switch requestedPath {
    case .home:
      "remote_base=\"$HOME\""
    case .absolute(let path):
      "remote_base=\(SSHCommandSupport.shellEscape(path))"
    case .homeRelative(let relativePath):
      if relativePath.isEmpty {
        "remote_base=\"$HOME\""
      } else {
        "remote_base=\"$HOME\"/\(SSHCommandSupport.shellEscape(relativePath))"
      }
    }
  }

  private func directoryListingFailureMessage(
    for output: RemoteExecutionClient.Output
  ) -> String {
    if output.stderr.contains("\(errorMarker)missing-directory") {
      return "The remote folder couldn't be opened."
    }
    return genericFailureMessage(
      prefix: "Couldn't browse remote folders.",
      detail: bestAvailableErrorDetail(from: output)
    )
  }

  private func repositoryValidationFailureMessage(
    for output: RemoteExecutionClient.Output
  ) -> String {
    if output.stderr.contains("\(errorMarker)missing-directory") {
      return "The remote folder doesn't exist."
    }
    if output.stderr.contains("\(errorMarker)not-git") {
      return "The selected folder is not a Git repository."
    }
    return genericFailureMessage(
      prefix: "Couldn't validate the remote repository.",
      detail: bestAvailableErrorDetail(from: output)
    )
  }

  private func genericFailureMessage(prefix: String, detail: String?) -> String {
    guard let detail, !detail.isEmpty else {
      return prefix
    }
    return "\(prefix)\n\(detail)"
  }

  private func bestAvailableErrorDetail(
    from output: RemoteExecutionClient.Output
  ) -> String? {
    let candidates = [output.stderr, output.stdout]
    for candidate in candidates {
      let lines = candidate
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.contains(errorMarker) }
      if let line = lines.first {
        return line
      }
    }
    return nil
  }

  private static func parentDirectory(of path: String) -> String {
    guard path != "/" else {
      return "/"
    }
    let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let parent = standardized.deletingLastPathComponent()
    let resolvedPath = parent.path(percentEncoded: false)
    return resolvedPath.isEmpty ? "/" : resolvedPath
  }
}

private struct HostFields {
  let displayName: String
  let host: String
  let user: String
  let port: Int?
  let authMethod: SSHHostProfile.AuthMethod
}

private enum RemotePathRequest {
  case home
  case absolute(String)
  case homeRelative(String)
}

private enum RequestedPathResult {
  case success(RemotePathRequest)
  case failure(String)
}

private let remoteCommandTimeoutSeconds = 15
private let errorMarker = "__PROWL_REMOTE_CONNECT__:"
