import ComposableArchitecture
import Foundation

@Reducer
struct WorktreeCreationPromptFeature {
  @ObservableState
  struct State: Equatable {
    let repositoryID: Repository.ID
    let repositoryName: String
    let automaticBaseRefLabel: String
    let baseRefOptions: [String]
    var branchName: String
    var selectedBaseRef: String?
    var validationMessage: String?
    var isValidating = false
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case createButtonTapped
    case setValidationMessage(String?)
    case setValidating(Bool)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case cancel
    case submit(repositoryID: Repository.ID, branchName: String, baseRef: String?)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.validationMessage = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancel))

      case .createButtonTapped:
        let trimmed = state.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          state.validationMessage = "Branch name required."
          return .none
        }
        guard !trimmed.contains(where: \.isWhitespace) else {
          state.validationMessage = "Branch names can't contain spaces."
          return .none
        }
        state.validationMessage = nil
        return .send(
          .delegate(
            .submit(
              repositoryID: state.repositoryID,
              branchName: trimmed,
              baseRef: state.selectedBaseRef
            )
          )
        )

      case .setValidationMessage(let message):
        state.validationMessage = message
        return .none

      case .setValidating(let isValidating):
        state.isValidating = isValidating
        return .none

      case .delegate:
        return .none
      }
    }
  }
}
