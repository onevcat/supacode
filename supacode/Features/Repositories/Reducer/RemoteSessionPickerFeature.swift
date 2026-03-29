import ComposableArchitecture
import Foundation

@Reducer
struct RemoteSessionPickerFeature {
  @ObservableState
  struct State: Equatable {
    let worktreeID: Worktree.ID
    let repositoryRootURL: URL
    let remotePath: String
    var sessions: [String]
    var selectedSessionName: String
    var managedSessionName: String

    init(
      worktreeID: Worktree.ID,
      repositoryRootURL: URL,
      remotePath: String,
      sessions: [String],
      preferredSessionName: String?,
      suggestedManagedSessionName: String?
    ) {
      self.worktreeID = worktreeID
      self.repositoryRootURL = repositoryRootURL
      self.remotePath = remotePath
      self.sessions = sessions
      let trimmedPreferred = preferredSessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedSelectedSessionName: String
      if let trimmedPreferred, sessions.contains(trimmedPreferred) {
        resolvedSelectedSessionName = trimmedPreferred
      } else {
        resolvedSelectedSessionName = sessions.first ?? ""
      }
      selectedSessionName = resolvedSelectedSessionName
      let trimmedSuggested = suggestedManagedSessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let trimmedSuggested, !trimmedSuggested.isEmpty {
        managedSessionName = trimmedSuggested
      } else {
        managedSessionName = Self.defaultManagedSessionName(for: remotePath)
      }
    }

    var canAttachSelectedSession: Bool {
      !selectedSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCreateManagedSession: Bool {
      !managedSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func defaultManagedSessionName(for remotePath: String) -> String {
      let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPath.isEmpty else {
        return "prowl"
      }
      let leaf = URL(fileURLWithPath: trimmedPath, isDirectory: true).lastPathComponent
      let trimmedLeaf = leaf.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedLeaf.isEmpty else {
        return "prowl"
      }
      return trimmedLeaf.replacing(" ", with: "-")
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case attachTapped
    case createAndAttachTapped
    case cancelTapped
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case cancel
    case attachExisting(String)
    case createAndAttach(String)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .attachTapped:
        let sessionName = state.selectedSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionName.isEmpty else {
          return .none
        }
        return .send(.delegate(.attachExisting(sessionName)))

      case .createAndAttachTapped:
        let sessionName = state.managedSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionName.isEmpty else {
          return .none
        }
        return .send(.delegate(.createAndAttach(sessionName)))

      case .cancelTapped:
        return .send(.delegate(.cancel))

      case .delegate:
        return .none
      }
    }
  }
}
