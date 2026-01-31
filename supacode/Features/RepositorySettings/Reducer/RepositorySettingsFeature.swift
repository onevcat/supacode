import ComposableArchitecture
import Foundation

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

  enum Action: Equatable {
    case task
    case settingsLoaded(RepositorySettings, isBareRepository: Bool)
    case branchDataLoaded([String], defaultBaseRef: String)
    case setSetupScript(String)
    case setRunScript(String)
    case setWorktreeBaseRef(String)
    case setCopyIgnoredOnWorktreeCreate(Bool)
    case setCopyUntrackedOnWorktreeCreate(Bool)
    case delegate(Delegate)
  }

  enum Delegate: Equatable {
    case settingsChanged(URL)
  }

  @Dependency(\.repositorySettingsClient) private var repositorySettingsClient
  @Dependency(\.gitClient) private var gitClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        let gitClient = gitClient
        return .run { send in
          let settings = repositorySettingsClient.load(rootURL)
          let isBareRepository = (try? await gitClient.isBareRepository(rootURL)) ?? false
          await send(.settingsLoaded(settings, isBareRepository: isBareRepository))
          let branches: [String]
          do {
            branches = try await gitClient.branchRefs(rootURL)
          } catch {
            let rootPath = rootURL.path(percentEncoded: false)
            print(
              "Repository settings branch refs failed for \(rootPath): "
                + error.localizedDescription
            )
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
        let repositorySettingsClient = repositorySettingsClient
        let settingsToSave = updatedSettings
        return .run { send in
          repositorySettingsClient.save(settingsToSave, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

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

      case .setSetupScript(let script):
        state.settings.setupScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setRunScript(let script):
        state.settings.runScript = script
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setWorktreeBaseRef(let ref):
        state.settings.worktreeBaseRef = ref
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setCopyIgnoredOnWorktreeCreate(let isEnabled):
        guard !state.isBareRepository else { return .none }
        state.settings.copyIgnoredOnWorktreeCreate = isEnabled
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .setCopyUntrackedOnWorktreeCreate(let isEnabled):
        guard !state.isBareRepository else { return .none }
        state.settings.copyUntrackedOnWorktreeCreate = isEnabled
        let settings = state.settings
        let rootURL = state.rootURL
        let repositorySettingsClient = repositorySettingsClient
        return .run { send in
          repositorySettingsClient.save(settings, rootURL)
          await send(.delegate(.settingsChanged(rootURL)))
        }

      case .delegate:
        return .none
      }
    }
  }
}
