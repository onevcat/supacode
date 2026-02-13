import ComposableArchitecture
import Foundation
import OSLog

@Reducer
struct RepositorySettingsFeature {
  @ObservableState
  struct State: Equatable {
    var rootURL: URL
    var settings: RepositorySettings
    var isBareRepository = false
    var branchOptions: [String] = []
    var defaultWorktreeBaseRef = "origin/main"
    var isBranchDataLoaded = false
  }

  enum Action: BindableAction {
    case task
    case settingsLoaded(RepositorySettings, isBareRepository: Bool)
    case branchDataLoaded([String], defaultBaseRef: String)
    case delegate(Delegate)
    case binding(BindingAction<State>)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(URL)
  }

  @Dependency(\.gitClient) private var gitClient

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        let rootURL = state.rootURL
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        let settings = repositorySettings
        let gitClient = gitClient
        return .run { send in
          let isBareRepository = (try? await gitClient.isBareRepository(rootURL)) ?? false
          await send(.settingsLoaded(settings, isBareRepository: isBareRepository))
          let branches: [String]
          do {
            branches = try await gitClient.branchRefs(rootURL)
          } catch {
            let rootPath = rootURL.path(percentEncoded: false)
            #if DEBUG
              print(
                "Repository settings branch refs failed for \(rootPath): "
                  + error.localizedDescription
              )
            #else
              Logger.supacode("Settings").warning(
                "Branch refs failed for \(rootPath): \(error.localizedDescription)"
              )
            #endif
            branches = []
          }
          let defaultBaseRef = await gitClient.automaticWorktreeBaseRef(rootURL) ?? "HEAD"
          await send(.branchDataLoaded(branches, defaultBaseRef: defaultBaseRef))
        }

      case .settingsLoaded(let settings, let isBareRepository):
        var updatedSettings = settings
        if isBareRepository {
          updatedSettings.copyIgnoredOnWorktreeCreate = false
          updatedSettings.copyUntrackedOnWorktreeCreate = false
        }
        state.settings = updatedSettings
        state.isBareRepository = isBareRepository
        guard isBareRepository, updatedSettings != settings else { return .none }
        let rootURL = state.rootURL
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        $repositorySettings.withLock { $0 = updatedSettings }
        return .send(.delegate(.settingsChanged(rootURL)))

      case .branchDataLoaded(let branches, let defaultBaseRef):
        state.defaultWorktreeBaseRef = defaultBaseRef
        var options = branches
        if !options.contains(defaultBaseRef) {
          options.append(defaultBaseRef)
        }
        if let selected = state.settings.worktreeBaseRef, !options.contains(selected) {
          options.append(selected)
        }
        state.branchOptions = options
        state.isBranchDataLoaded = true
        return .none

      case .binding:
        if state.isBareRepository {
          state.settings.copyIgnoredOnWorktreeCreate = false
          state.settings.copyUntrackedOnWorktreeCreate = false
        }
        let rootURL = state.rootURL
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        $repositorySettings.withLock { $0 = state.settings }
        return .send(.delegate(.settingsChanged(rootURL)))

      case .delegate:
        return .none
      }
    }
  }
}
