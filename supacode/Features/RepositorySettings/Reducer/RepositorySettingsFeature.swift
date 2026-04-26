import ComposableArchitecture
import Foundation

@Reducer
struct RepositorySettingsFeature {
  @ObservableState
  struct State: Equatable {
    var rootURL: URL
    /// Persistence key for `@Shared(.repositoryAppearances)`. Defaults
    /// to empty so legacy test fixtures that only construct the four
    /// originally-required fields keep compiling — production
    /// callers (AppFeature) always pass the canonical `repository.id`.
    var repositoryID: Repository.ID = ""
    var repositoryKind: Repository.Kind
    var settings: RepositorySettings
    var userSettings: UserRepositorySettings
    var appearance: RepositoryAppearance = .empty
    var globalDefaultWorktreeBaseDirectoryPath: String?
    var globalCopyIgnoredOnWorktreeCreate: Bool = false
    var globalCopyUntrackedOnWorktreeCreate: Bool = false
    var globalPullRequestMergeStrategy: PullRequestMergeStrategy = .merge
    var isBareRepository = false
    var branchOptions: [String] = []
    var defaultWorktreeBaseRef = "origin/main"
    var isBranchDataLoaded = false
    var keybindingUserOverrides: KeybindingUserOverrideStore = .empty
    var appearanceImportError: String?

    var capabilities: Repository.Capabilities {
      switch repositoryKind {
      case .git:
        .git
      case .plain:
        .plain
      }
    }

    var showsWorktreeSettings: Bool {
      capabilities.supportsWorktrees
    }

    var showsPullRequestSettings: Bool {
      capabilities.supportsPullRequests
    }

    var showsSetupScriptSettings: Bool {
      capabilities.supportsWorktrees
    }

    var showsArchiveScriptSettings: Bool {
      capabilities.supportsWorktrees
    }

    var showsRunScriptSettings: Bool {
      capabilities.supportsRunnableFolderActions
    }

    var showsCustomCommandsSettings: Bool {
      capabilities.supportsRunnableFolderActions
    }

    var exampleWorktreePath: String {
      SupacodePaths.exampleWorktreePath(
        for: rootURL,
        globalDefaultPath: globalDefaultWorktreeBaseDirectoryPath,
        repositoryOverridePath: settings.worktreeBaseDirectoryPath
      )
    }
  }

  enum Action: BindableAction {
    case task
    case settingsLoaded(
      RepositorySettings,
      UserRepositorySettings,
      isBareRepository: Bool,
      globalDefaultWorktreeBaseDirectoryPath: String?,
      globalCopyIgnoredOnWorktreeCreate: Bool,
      globalCopyUntrackedOnWorktreeCreate: Bool,
      globalPullRequestMergeStrategy: PullRequestMergeStrategy,
      keybindingUserOverrides: KeybindingUserOverrideStore
    )
    case appearanceLoaded(RepositoryAppearance)
    case setAppearanceColor(RepositoryColorChoice?)
    case setAppearanceIcon(RepositoryIconSource?)
    case importUserImage(URL)
    case userImageImported(filename: String)
    case userImageImportFailed(String)
    case dismissAppearanceImportError
    case resetAppearance
    case branchDataLoaded([String], defaultBaseRef: String)
    case delegate(Delegate)
    case binding(BindingAction<State>)
  }

  @CasePathable
  enum Delegate: Equatable {
    case settingsChanged(URL)
  }

  @Dependency(GitClientDependency.self) private var gitClient
  @Dependency(\.repositoryIconAssetStore) private var repositoryIconAssetStore

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        let rootURL = state.rootURL
        let repositoryID = state.repositoryID
        guard state.capabilities.supportsRepositoryGitSettings else {
          return .run { send in
            @Shared(.repositorySettings(rootURL)) var repositorySettings
            @Shared(.userRepositorySettings(rootURL)) var userRepositorySettings
            @Shared(.settingsFile) var settingsFile
            @Shared(.repositoryAppearances) var appearances
            let global = settingsFile.global
            await send(
              .settingsLoaded(
                repositorySettings,
                userRepositorySettings,
                isBareRepository: false,
                globalDefaultWorktreeBaseDirectoryPath: global.defaultWorktreeBaseDirectoryPath,
                globalCopyIgnoredOnWorktreeCreate: global.copyIgnoredOnWorktreeCreate,
                globalCopyUntrackedOnWorktreeCreate: global.copyUntrackedOnWorktreeCreate,
                globalPullRequestMergeStrategy: global.pullRequestMergeStrategy,
                keybindingUserOverrides: global.keybindingUserOverrides
              )
            )
            if let appearance = appearances[repositoryID], !appearance.isEmpty {
              await send(.appearanceLoaded(appearance))
            }
          }
        }
        let gitClient = gitClient
        return .run { send in
          let isBareRepository = (try? await gitClient.isBareRepository(rootURL)) ?? false
          @Shared(.repositorySettings(rootURL)) var repositorySettings
          @Shared(.userRepositorySettings(rootURL)) var userRepositorySettings
          @Shared(.settingsFile) var settingsFile
          @Shared(.repositoryAppearances) var appearances
          let global = settingsFile.global
          await send(
            .settingsLoaded(
              repositorySettings,
              userRepositorySettings,
              isBareRepository: isBareRepository,
              globalDefaultWorktreeBaseDirectoryPath: global.defaultWorktreeBaseDirectoryPath,
              globalCopyIgnoredOnWorktreeCreate: global.copyIgnoredOnWorktreeCreate,
              globalCopyUntrackedOnWorktreeCreate: global.copyUntrackedOnWorktreeCreate,
              globalPullRequestMergeStrategy: global.pullRequestMergeStrategy,
              keybindingUserOverrides: global.keybindingUserOverrides
            )
          )
          if let appearance = appearances[repositoryID], !appearance.isEmpty {
            await send(.appearanceLoaded(appearance))
          }
          let branches: [String]
          do {
            branches = try await gitClient.branchRefs(rootURL)
          } catch {
            let rootPath = rootURL.path(percentEncoded: false)
            SupaLogger("Settings").warning(
              "Branch refs failed for \(rootPath): \(error.localizedDescription)"
            )
            branches = []
          }
          let defaultBaseRef = await gitClient.automaticWorktreeBaseRef(rootURL) ?? "HEAD"
          await send(.branchDataLoaded(branches, defaultBaseRef: defaultBaseRef))
        }

      case .settingsLoaded(
        let settings,
        let userSettings,
        let isBareRepository,
        let globalDefaultWorktreeBaseDirectoryPath,
        let globalCopyIgnoredOnWorktreeCreate,
        let globalCopyUntrackedOnWorktreeCreate,
        let globalPullRequestMergeStrategy,
        let keybindingUserOverrides
      ):
        var updatedSettings = settings
        updatedSettings.worktreeBaseDirectoryPath = SupacodePaths.normalizedWorktreeBaseDirectoryPath(
          updatedSettings.worktreeBaseDirectoryPath,
          repositoryRootURL: state.rootURL
        )
        if isBareRepository {
          updatedSettings.copyIgnoredOnWorktreeCreate = nil
          updatedSettings.copyUntrackedOnWorktreeCreate = nil
        }
        state.settings = updatedSettings
        state.userSettings = userSettings.normalized()
        state.globalDefaultWorktreeBaseDirectoryPath =
          SupacodePaths.normalizedWorktreeBaseDirectoryPath(globalDefaultWorktreeBaseDirectoryPath)
        state.globalCopyIgnoredOnWorktreeCreate = globalCopyIgnoredOnWorktreeCreate
        state.globalCopyUntrackedOnWorktreeCreate = globalCopyUntrackedOnWorktreeCreate
        state.globalPullRequestMergeStrategy = globalPullRequestMergeStrategy
        state.isBareRepository = isBareRepository
        state.keybindingUserOverrides = keybindingUserOverrides
        guard updatedSettings != settings else { return .none }
        let rootURL = state.rootURL
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        $repositorySettings.withLock { $0 = updatedSettings }
        return .send(.delegate(.settingsChanged(rootURL)))

      case .appearanceLoaded(let appearance):
        state.appearance = appearance
        return .none

      case .setAppearanceColor(let color):
        guard state.appearance.color != color else { return .none }
        state.appearance.color = color
        return persistAppearance(state.appearance, repositoryID: state.repositoryID)

      case .setAppearanceIcon(let newIcon):
        let previousIcon = state.appearance.icon
        guard previousIcon != newIcon else { return .none }
        state.appearance.icon = newIcon
        let persist = persistAppearance(state.appearance, repositoryID: state.repositoryID)
        let cleanup = removeAbandonedUserImage(
          previous: previousIcon,
          new: newIcon,
          rootURL: state.rootURL
        )
        return .merge(persist, cleanup)

      case .importUserImage(let sourceURL):
        let rootURL = state.rootURL
        let store = repositoryIconAssetStore
        return .run { send in
          do {
            let filename = try store.importImage(sourceURL, rootURL)
            await send(.userImageImported(filename: filename))
          } catch let error as RepositoryIconAssetStoreError {
            await send(.userImageImportFailed(Self.errorMessage(for: error)))
          } catch {
            await send(.userImageImportFailed(error.localizedDescription))
          }
        }

      case .userImageImported(let filename):
        return .send(.setAppearanceIcon(.userImage(filename: filename)))

      case .userImageImportFailed(let message):
        state.appearanceImportError = message
        return .none

      case .dismissAppearanceImportError:
        state.appearanceImportError = nil
        return .none

      case .resetAppearance:
        let previousIcon = state.appearance.icon
        guard !state.appearance.isEmpty else { return .none }
        state.appearance = .empty
        let persist = persistAppearance(.empty, repositoryID: state.repositoryID)
        let cleanup = removeAbandonedUserImage(
          previous: previousIcon,
          new: nil,
          rootURL: state.rootURL
        )
        return .merge(persist, cleanup)

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
          state.settings.copyIgnoredOnWorktreeCreate = nil
          state.settings.copyUntrackedOnWorktreeCreate = nil
        }
        state.userSettings = state.userSettings.normalized()
        let rootURL = state.rootURL
        var normalizedSettings = state.settings
        normalizedSettings.worktreeBaseDirectoryPath = SupacodePaths.normalizedWorktreeBaseDirectoryPath(
          normalizedSettings.worktreeBaseDirectoryPath,
          repositoryRootURL: rootURL
        )
        @Shared(.repositorySettings(rootURL)) var repositorySettings
        @Shared(.userRepositorySettings(rootURL)) var userRepositorySettings
        $repositorySettings.withLock { $0 = normalizedSettings }
        $userRepositorySettings.withLock { $0 = state.userSettings }
        return .send(.delegate(.settingsChanged(rootURL)))

      case .delegate:
        return .none
      }
    }
  }

  /// Writes the appearance back to the global `@Shared` dict, dropping
  /// the entry when it's been cleared so the on-disk file stays tight.
  private func persistAppearance(
    _ appearance: RepositoryAppearance,
    repositoryID: Repository.ID
  ) -> Effect<Action> {
    .run { _ in
      @Shared(.repositoryAppearances) var appearances
      $appearances.withLock {
        if appearance.isEmpty {
          $0.removeValue(forKey: repositoryID)
        } else {
          $0[repositoryID] = appearance
        }
      }
    }
  }

  /// When the icon transitions away from a user-imported file, the old
  /// asset on disk is no longer referenced and should be cleaned up.
  /// No-op when the previous icon wasn't a user image or when the new
  /// icon is the same user image.
  private func removeAbandonedUserImage(
    previous: RepositoryIconSource?,
    new: RepositoryIconSource?,
    rootURL: URL
  ) -> Effect<Action> {
    guard case .userImage(let oldFilename) = previous else { return .none }
    if case .userImage(let newFilename) = new, newFilename == oldFilename {
      return .none
    }
    let store = repositoryIconAssetStore
    return .run { _ in
      try? store.remove(oldFilename, rootURL)
    }
  }

  private static func errorMessage(for error: RepositoryIconAssetStoreError) -> String {
    switch error {
    case .unsupportedExtension(let ext):
      return "Repository icons must be PNG or SVG. \(ext.uppercased()) files aren't supported."
    }
  }
}
