import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct RemoteGroupsFeature {
  nonisolated struct EndpointSessionsError: Error, Equatable, Sendable {
    var message: String
  }

  @ObservableState
  struct State: Equatable {
    @Shared(.appStorage("remoteGroups_endpoints")) var endpoints: [RemoteEndpoint] = []
    @Shared(.appStorage("remoteGroups_selection")) var selection: RemoteSelection = .none
    var groupsByEndpointID: [UUID: [RemoteGroupRef]] = [:]
    var isAddPromptPresented = false
    var addURLDraft = ""
    var addGroupDraft = ""
    var loadingEndpointIDs: Set<UUID> = []
    var errorByEndpointID: [UUID: String] = [:]
  }

  enum Action: Equatable {
    case setAddPromptPresented(Bool)
    case addURLDraftChanged(String)
    case addGroupDraftChanged(String)
    case submitEndpoint(urlText: String, initialGroup: String)
    case clearSelection
    case fetchEndpointSessions(UUID)
    case endpointSessionsResponse(endpointID: UUID, result: Result<[RemoteTerminalSession], EndpointSessionsError>)
    case selectOverview(UUID)
    case selectGroup(endpointID: UUID, group: String)
  }

  @Dependency(RemoteTerminalClient.self) var remoteTerminalClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .setAddPromptPresented(let presented):
        state.isAddPromptPresented = presented
        if !presented {
          state.addURLDraft = ""
          state.addGroupDraft = ""
        }
        return .none

      case .addURLDraftChanged(let value):
        state.addURLDraft = value
        return .none

      case .addGroupDraftChanged(let value):
        state.addGroupDraft = value
        return .none

      case .submitEndpoint(let urlText, let initialGroup):
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL = URL(string: trimmed),
          rawURL.scheme != nil,
          rawURL.host != nil
        else {
          return .none
        }

        let normalizedURL = rawURL.absoluteString.hasSuffix("/") ? rawURL : rawURL.appending(path: "")
        let endpoint: RemoteEndpoint
        if let existing = state.endpoints.first(where: { $0.baseURL == normalizedURL }) {
          endpoint = existing
        } else {
          let created = RemoteEndpoint(baseURL: normalizedURL)
          state.$endpoints.withLock {
            $0.append(created)
          }
          endpoint = created
        }

        let trimmedGroup = initialGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGroup.isEmpty {
          state.$selection.withLock {
            $0 = .overview(endpointID: endpoint.id)
          }
        } else {
          let group = RemoteGroupParsing.slugify(trimmedGroup)
          state.$selection.withLock {
            $0 = group.isEmpty ? .overview(endpointID: endpoint.id) : .group(endpointID: endpoint.id, group: group)
          }
        }

        state.isAddPromptPresented = false
        state.addURLDraft = ""
        state.addGroupDraft = ""
        return .send(.fetchEndpointSessions(endpoint.id))

      case .clearSelection:
        state.$selection.withLock {
          $0 = .none
        }
        return .none

      case .fetchEndpointSessions(let endpointID):
        guard let endpoint = state.endpoints.first(where: { $0.id == endpointID }) else {
          return .none
        }

        state.loadingEndpointIDs.insert(endpointID)
        state.errorByEndpointID[endpointID] = nil

        return .run { send in
          do {
            let sessions = try await remoteTerminalClient.listSessions(endpoint.baseURL)
            await send(.endpointSessionsResponse(endpointID: endpointID, result: .success(sessions)))
          } catch {
            await send(
              .endpointSessionsResponse(
                endpointID: endpointID,
                result: .failure(.init(message: error.localizedDescription))
              )
            )
          }
        }

      case .endpointSessionsResponse(let endpointID, let result):
        state.loadingEndpointIDs.remove(endpointID)

        switch result {
        case .success(let sessions):
          state.groupsByEndpointID[endpointID] = RemoteGroupRef.aggregate(sessions: sessions)
          state.errorByEndpointID[endpointID] = nil

        case .failure(let error):
          state.groupsByEndpointID[endpointID] = []
          state.errorByEndpointID[endpointID] = error.message
        }

        return .none

      case .selectOverview(let endpointID):
        state.$selection.withLock {
          $0 = .overview(endpointID: endpointID)
        }
        return .none

      case .selectGroup(let endpointID, let group):
        state.$selection.withLock {
          $0 = .group(endpointID: endpointID, group: group)
        }
        return .none
      }
    }
  }
}
