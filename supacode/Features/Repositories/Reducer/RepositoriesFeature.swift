import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import PostHog
import SwiftUI

nonisolated let githubIntegrationRecoveryInterval: Duration = .seconds(15)
nonisolated let worktreeCreationProgressLineLimit = 200
nonisolated let worktreeCreationProgressUpdateStride = 20
nonisolated let archiveScriptProgressLineLimit = 200
private let secondsPerDay: Double = 86_400

nonisolated struct WorktreeCreationProgressUpdateThrottle {
  private let stride: Int
  private var hasEmittedFirstLine = false
  private var unsentLineCount = 0

  init(stride: Int) {
    precondition(stride > 0)
    self.stride = stride
  }

  mutating func recordLine() -> Bool {
    unsentLineCount += 1
    if !hasEmittedFirstLine {
      hasEmittedFirstLine = true
      unsentLineCount = 0
      return true
    }
    if unsentLineCount >= stride {
      unsentLineCount = 0
      return true
    }
    return false
  }

  mutating func flush() -> Bool {
    guard unsentLineCount > 0 else {
      return false
    }
    unsentLineCount = 0
    return true
  }
}

@Reducer
struct RepositoriesFeature {
  enum CancelID {
    static let load = "repositories.load"
    static let toastAutoDismiss = "repositories.toastAutoDismiss"
    static let githubIntegrationAvailability = "repositories.githubIntegrationAvailability"
    static let githubIntegrationRecovery = "repositories.githubIntegrationRecovery"
    static let worktreePromptLoad = "repositories.worktreePromptLoad"
    static let worktreePromptValidation = "repositories.worktreePromptValidation"
    static func archiveScript(_ worktreeID: Worktree.ID) -> String {
      "repositories.archiveScript.\(worktreeID)"
    }
    static func delayedPRRefresh(_ worktreeID: Worktree.ID) -> String {
      "repositories.delayedPRRefresh.\(worktreeID)"
    }
  }

  @CasePathable
  enum WorktreeCreationAction: Equatable {
    case promptCanceled
    case promptDismissed
    case createRandomWorktree
    case createRandomWorktreeInRepository(Repository.ID)
    case createWorktreeInRepository(
      repositoryID: Repository.ID,
      nameSource: WorktreeCreationNameSource,
      baseRefSource: WorktreeCreationBaseRefSource
    )
    case promptedWorktreeCreationDataLoaded(
      repositoryID: Repository.ID,
      baseRefOptions: [String],
      automaticBaseRefLabel: String,
      selectedBaseRef: String?
    )
    case startPromptedWorktreeCreation(
      repositoryID: Repository.ID,
      branchName: String,
      baseRef: String?
    )
    case promptedWorktreeCreationChecked(
      repositoryID: Repository.ID,
      branchName: String,
      baseRef: String?,
      duplicateMessage: String?
    )
    case pendingWorktreeProgressUpdated(id: Worktree.ID, progress: WorktreeCreationProgress)
    case createRandomWorktreeSucceeded(
      Worktree,
      repositoryID: Repository.ID,
      pendingID: Worktree.ID
    )
    case createRandomWorktreeFailed(
      title: String,
      message: String,
      pendingID: Worktree.ID,
      previousSelection: Worktree.ID?,
      repositoryID: Repository.ID,
      name: String?,
      baseDirectory: URL
    )
    case consumeSetupScript(Worktree.ID)
    case consumeTerminalFocus(Worktree.ID)
  }

  @CasePathable
  enum WorktreeLifecycleAction: Equatable {
    case requestArchiveWorktree(Worktree.ID, Repository.ID)
    case requestArchiveWorktrees([ArchiveWorktreeTarget])
    case archiveWorktreeConfirmed(Worktree.ID, Repository.ID)
    case archiveScriptProgressUpdated(worktreeID: Worktree.ID, progress: ArchiveScriptProgress)
    case archiveScriptSucceeded(worktreeID: Worktree.ID, repositoryID: Repository.ID)
    case archiveScriptFailed(worktreeID: Worktree.ID, message: String)
    case archiveWorktreeApply(Worktree.ID, Repository.ID)
    case unarchiveWorktree(Worktree.ID)
    case requestDeleteWorktree(Worktree.ID, Repository.ID)
    case requestDeleteWorktrees([DeleteWorktreeTarget])
    case deleteWorktreeConfirmed(Worktree.ID, Repository.ID)
    case worktreeDeleted(
      Worktree.ID,
      repositoryID: Repository.ID,
      selectionWasRemoved: Bool,
      nextSelection: Worktree.ID?
    )
    case deleteWorktreeFailed(String, worktreeID: Worktree.ID)
  }

  @CasePathable
  enum WorktreeOrderingAction: Equatable {
    case repositoriesMoved(IndexSet, Int)
    case pinnedWorktreesMoved(repositoryID: Repository.ID, IndexSet, Int)
    case unpinnedWorktreesMoved(repositoryID: Repository.ID, IndexSet, Int)
    case pinWorktree(Worktree.ID)
    case unpinWorktree(Worktree.ID)
    case worktreeNotificationReceived(Worktree.ID)
    case setMoveNotifiedWorktreeToTop(Bool)
  }

  @CasePathable
  enum GithubIntegrationAction: Equatable {
    case delayedPullRequestRefresh(Worktree.ID)
    case repositoryPullRequestRefreshRequested(repositoryRootURL: URL, worktreeIDs: [Worktree.ID])
    case refreshGithubIntegrationAvailability
    case githubIntegrationAvailabilityUpdated(Bool)
    case repositoryPullRequestRefreshCompleted(Repository.ID)
    case repositoryPullRequestsLoaded(
      repositoryID: Repository.ID,
      pullRequestsByWorktreeID: [Worktree.ID: GithubPullRequest?]
    )
    case setGithubIntegrationEnabled(Bool)
    case setAutomaticallyArchiveMergedWorktrees(Bool)
    case pullRequestAction(Worktree.ID, PullRequestAction)
  }

  @CasePathable
  enum RepositoryManagementAction: Equatable {
    case openRepositories([URL])
    case openRepositoriesFinished(
      [Repository],
      failures: [LoadFailure],
      invalidRoots: [String],
      openFailures: [String],
      roots: [URL]
    )
    case requestRemoveRepository(Repository.ID)
    case removeFailedRepository(Repository.ID)
    case repositoryRemoved(Repository.ID, selectionWasRemoved: Bool)
    case openRepositorySettings(Repository.ID)
  }

  @ObservableState
  struct State: Equatable {
    var repositories: IdentifiedArrayOf<Repository> = []
    var repositoryRoots: [URL] = []
    var repositoryOrderIDs: [Repository.ID] = []
    var loadFailuresByID: [Repository.ID: String] = [:]
    var selection: SidebarSelection?
    var worktreeInfoByID: [Worktree.ID: WorktreeInfoEntry] = [:]
    var worktreeOrderByRepository: [Repository.ID: [Worktree.ID]] = [:]
    var isOpenPanelPresented = false
    var isInitialLoadComplete = false
    var pendingWorktrees: [PendingWorktree] = []
    var pendingSetupScriptWorktreeIDs: Set<Worktree.ID> = []
    var pendingTerminalFocusWorktreeIDs: Set<Worktree.ID> = []
    var archivingWorktreeIDs: Set<Worktree.ID> = []
    var archiveScriptProgressByWorktreeID: [Worktree.ID: ArchiveScriptProgress] = [:]
    var deletingWorktreeIDs: Set<Worktree.ID> = []
    var removingRepositoryIDs: Set<Repository.ID> = []
    var pinnedWorktreeIDs: [Worktree.ID] = []
    var archivedWorktrees: [ArchivedWorktree] = []
    var archivedAutoDeletePeriod: AutoDeletePeriod?
    var automaticallyArchiveMergedWorktrees = false
    var moveNotifiedWorktreeToTop = true
    var lastFocusedWorktreeID: Worktree.ID?
    var preCanvasWorktreeID: Worktree.ID?
    var preCanvasTerminalTargetID: Worktree.ID?
    var launchRestoreMode: LaunchRestoreMode = .lastFocusedWorktree
    var shouldRestoreLastFocusedWorktree = false
    var shouldSelectFirstAfterReload = false
    var isRefreshingWorktrees = false
    var statusToast: StatusToast?
    var snapshotPersistencePhase: SnapshotPersistencePhase = .idle
    var githubIntegrationAvailability: GithubIntegrationAvailability = .unknown
    var pendingPullRequestRefreshByRepositoryID: [Repository.ID: PendingPullRequestRefresh] = [:]
    var inFlightPullRequestRefreshRepositoryIDs: Set<Repository.ID> = []
    var queuedPullRequestRefreshByRepositoryID: [Repository.ID: PendingPullRequestRefresh] = [:]
    var sidebarSelectedWorktreeIDs: Set<Worktree.ID> = []
    @Shared(.appStorage("sidebarCollapsedRepositoryIDs")) var collapsedRepositoryIDs: [Repository.ID] = []
    @Presents var worktreeCreationPrompt: WorktreeCreationPromptFeature.State?
    @Presents var alert: AlertState<Alert>?
  }

  enum GithubIntegrationAvailability: Equatable {
    case unknown
    case checking
    case available
    case unavailable
    case disabled
  }

  struct PendingPullRequestRefresh: Equatable {
    var repositoryRootURL: URL
    var worktreeIDs: [Worktree.ID]
  }

  enum WorktreeCreationNameSource: Equatable {
    case random
    case explicit(String)
  }

  enum WorktreeCreationBaseRefSource: Equatable {
    case repositorySetting
    case explicit(String?)
  }

  enum Action {
    case worktreeCreation(WorktreeCreationAction)
    case worktreeLifecycle(WorktreeLifecycleAction)
    case worktreeOrdering(WorktreeOrderingAction)
    case githubIntegration(GithubIntegrationAction)
    case repositoryManagement(RepositoryManagementAction)
    case task
    case repositorySnapshotLoaded([Repository]?)
    case setOpenPanelPresented(Bool)
    case loadPersistedRepositories
    case pinnedWorktreeIDsLoaded([Worktree.ID])
    case archivedWorktreesLoaded([ArchivedWorktree])
    case setArchivedAutoDeletePeriod(AutoDeletePeriod?)
    case autoDeleteExpiredArchivedWorktrees
    case repositoryOrderIDsLoaded([Repository.ID])
    case worktreeOrderByRepositoryLoaded([Repository.ID: [Worktree.ID]])
    case lastFocusedWorktreeIDLoaded(Worktree.ID?)
    case refreshWorktrees
    case reloadRepositories(animated: Bool)
    case repositoriesLoaded([Repository], failures: [LoadFailure], roots: [URL], animated: Bool)
    case selectArchivedWorktrees
    case selectCanvas
    case toggleCanvas
    case setSidebarSelectedWorktreeIDs(Set<Worktree.ID>)
    case selectRepository(Repository.ID?)
    case selectWorktree(Worktree.ID?, focusTerminal: Bool = false)
    case selectNextWorktree
    case selectPreviousWorktree
    case requestRenameBranch(Worktree.ID, String)
    case presentAlert(title: String, message: String)
    case worktreeInfoEvent(WorktreeInfoWatcherClient.Event)
    case worktreeBranchNameLoaded(worktreeID: Worktree.ID, name: String)
    case worktreeLineChangesLoaded(worktreeID: Worktree.ID, added: Int, removed: Int)
    case showToast(StatusToast)
    case dismissToast
    case worktreeCreationPrompt(PresentationAction<WorktreeCreationPromptFeature.Action>)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
  }

  struct LoadFailure: Equatable {
    let rootID: Repository.ID
    let message: String
  }

  struct DeleteWorktreeTarget: Equatable {
    let worktreeID: Worktree.ID
    let repositoryID: Repository.ID
  }

  struct ArchiveWorktreeTarget: Equatable {
    let worktreeID: Worktree.ID
    let repositoryID: Repository.ID
  }

  struct ApplyRepositoriesResult {
    let didPrunePinned: Bool
    let didPruneRepositoryOrder: Bool
    let didPruneWorktreeOrder: Bool
    let didPruneArchivedWorktrees: Bool
  }

  enum StatusToast: Equatable {
    case inProgress(String)
    case success(String)
    case warning(String)
  }

  enum SnapshotPersistencePhase: Equatable {
    case idle
    case restoring
    case active
  }

  enum Alert: Equatable {
    case confirmArchiveWorktree(Worktree.ID, Repository.ID)
    case confirmArchiveWorktrees([ArchiveWorktreeTarget])
    case confirmDeleteWorktree(Worktree.ID, Repository.ID)
    case confirmDeleteWorktrees([DeleteWorktreeTarget])
    case confirmRemoveRepository(Repository.ID)
  }

  enum PullRequestAction: Equatable {
    case openOnGithub
    case markReadyForReview
    case merge
    case close
    case copyFailingJobURL
    case copyCiFailureLogs
    case rerunFailedJobs
    case openFailingCheckDetails
  }

  @CasePathable
  enum Delegate: Equatable {
    case selectedWorktreeChanged(Worktree?)
    case repositoriesChanged(IdentifiedArrayOf<Repository>)
    case openRepositorySettings(Repository.ID)
    case worktreeCreated(Worktree)
  }

  @Dependency(TerminalClient.self) var terminalClient
  @Dependency(AnalyticsClient.self) var analyticsClient
  @Dependency(GitClientDependency.self) var gitClient
  @Dependency(GithubCLIClient.self) var githubCLI
  @Dependency(GithubIntegrationClient.self) var githubIntegration
  @Dependency(RepositoryPersistenceClient.self) var repositoryPersistence
  @Dependency(ShellClient.self) var shellClient
  @Dependency(\.date.now) var now
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    CombineReducers {
      Reduce { state, action in
        switch action {
        case .worktreeCreation, .worktreeLifecycle, .worktreeOrdering, .githubIntegration, .repositoryManagement:
          return .none

        case .task:
          state.snapshotPersistencePhase = .restoring
          return .run { send in
            let pinned = await repositoryPersistence.loadPinnedWorktreeIDs()
            let archived = await repositoryPersistence.loadArchivedWorktrees()
            let lastFocused = await repositoryPersistence.loadLastFocusedWorktreeID()
            let repositoryOrderIDs = await repositoryPersistence.loadRepositoryOrderIDs()
            let worktreeOrderByRepository =
              await repositoryPersistence.loadWorktreeOrderByRepository()
            let repositorySnapshot = await repositoryPersistence.loadRepositorySnapshot()
            await send(.pinnedWorktreeIDsLoaded(pinned))
            await send(.archivedWorktreesLoaded(archived))
            await send(.repositoryOrderIDsLoaded(repositoryOrderIDs))
            await send(.worktreeOrderByRepositoryLoaded(worktreeOrderByRepository))
            await send(.lastFocusedWorktreeIDLoaded(lastFocused))
            await send(.repositorySnapshotLoaded(repositorySnapshot))
            await send(.loadPersistedRepositories)
          }

        case .repositorySnapshotLoaded(let repositories):
          guard let repositories, !repositories.isEmpty else {
            return .none
          }
          state.isRefreshingWorktrees = false
          let roots = repositories.map(\.rootURL)
          let previousSelection = state.selectedWorktreeID
          let previousSelectedWorktree = state.worktree(for: previousSelection)
          let incomingRepositories = IdentifiedArray(uniqueElements: repositories)
          let repositoriesChanged = incomingRepositories != state.repositories
          _ = applyRepositories(
            repositories,
            roots: roots,
            shouldPruneArchivedWorktrees: true,
            state: &state,
            animated: false
          )
          state.repositoryRoots = roots
          state.isInitialLoadComplete = true
          state.loadFailuresByID = [:]
          let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
          let selectionChanged = selectionDidChange(
            previousSelectionID: previousSelection,
            previousSelectedWorktree: previousSelectedWorktree,
            selectedWorktreeID: state.selectedWorktreeID,
            selectedWorktree: selectedWorktree
          )
          var allEffects: [Effect<Action>] = []
          if repositoriesChanged {
            allEffects.append(.send(.delegate(.repositoriesChanged(state.repositories))))
          }
          if selectionChanged {
            allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
          }
          return .merge(allEffects)

        case .pinnedWorktreeIDsLoaded(let pinnedWorktreeIDs):
          state.pinnedWorktreeIDs = pinnedWorktreeIDs
          return .none

        case .archivedWorktreesLoaded(let archivedWorktrees):
          state.archivedWorktrees = archivedWorktrees
          return .none

        case .setArchivedAutoDeletePeriod(let period):
          state.archivedAutoDeletePeriod = period
          guard period != nil else { return .none }
          return .send(.autoDeleteExpiredArchivedWorktrees)

        case .autoDeleteExpiredArchivedWorktrees:
          guard let period = state.archivedAutoDeletePeriod else {
            return .none
          }
          let cutoff = now.addingTimeInterval(-Double(period.rawValue) * secondsPerDay)
          let expiredEntries = state.archivedWorktrees.filter { $0.archivedAt <= cutoff }
          guard !expiredEntries.isEmpty else {
            return .none
          }
          var deleteEffects: [Effect<Action>] = []
          for entry in expiredEntries {
            guard
              let (worktree, repository) = findWorktreeAndRepository(
                worktreeID: entry.id,
                state: state
              ),
              !state.isMainWorktree(worktree),
              !state.deletingWorktreeIDs.contains(entry.id)
            else {
              continue
            }
            deleteEffects.append(
              .send(.worktreeLifecycle(.deleteWorktreeConfirmed(worktree.id, repository.id)))
            )
          }
          guard !deleteEffects.isEmpty else {
            return .none
          }
          return .merge(deleteEffects)

        case .repositoryOrderIDsLoaded(let repositoryOrderIDs):
          state.repositoryOrderIDs = repositoryOrderIDs
          return .none

        case .worktreeOrderByRepositoryLoaded(let worktreeOrderByRepository):
          state.worktreeOrderByRepository = worktreeOrderByRepository
          return .none

        case .lastFocusedWorktreeIDLoaded(let lastFocusedWorktreeID):
          state.lastFocusedWorktreeID = lastFocusedWorktreeID
          if state.launchRestoreMode == .lastFocusedWorktree {
            state.shouldRestoreLastFocusedWorktree = true
          }
          return .none

        case .setOpenPanelPresented(let isPresented):
          state.isOpenPanelPresented = isPresented
          return .none

        case .loadPersistedRepositories:
          state.alert = nil
          state.isRefreshingWorktrees = false
          return .run { send in
            let entries = await loadPersistedRepositoryEntries()
            let roots = entries.map { URL(fileURLWithPath: $0.path) }
            let (repositories, failures) = await loadRepositoriesData(entries)
            await send(
              .repositoriesLoaded(
                repositories,
                failures: failures,
                roots: roots,
                animated: false
              )
            )
          }
          .cancellable(id: CancelID.load, cancelInFlight: true)

        case .refreshWorktrees:
          state.isRefreshingWorktrees = true
          return .send(.reloadRepositories(animated: false))

        case .reloadRepositories(let animated):
          state.alert = nil
          let roots = state.repositoryRoots
          guard !roots.isEmpty else {
            state.isRefreshingWorktrees = false
            return .none
          }
          return loadRepositories(fallbackRoots: roots, animated: animated)

        case .repositoriesLoaded(let repositories, let failures, let roots, let animated):
          state.isRefreshingWorktrees = false
          let wasRestoringSnapshot = state.snapshotPersistencePhase == .restoring
          if failures.isEmpty, state.snapshotPersistencePhase != .active {
            state.snapshotPersistencePhase = .active
          }
          let previousSelection = state.selectedWorktreeID
          let previousSelectedWorktree = state.worktree(for: previousSelection)
          let incomingRepositories = IdentifiedArray(uniqueElements: repositories)
          let repositoriesChanged = incomingRepositories != state.repositories
          let applyResult = applyRepositories(
            repositories,
            roots: roots,
            shouldPruneArchivedWorktrees: failures.isEmpty,
            state: &state,
            animated: animated
          )
          state.repositoryRoots = roots
          state.isInitialLoadComplete = true
          state.loadFailuresByID = Dictionary(
            uniqueKeysWithValues: failures.map { ($0.rootID, $0.message) }
          )
          let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
          let selectionChanged = selectionDidChange(
            previousSelectionID: previousSelection,
            previousSelectedWorktree: previousSelectedWorktree,
            selectedWorktreeID: state.selectedWorktreeID,
            selectedWorktree: selectedWorktree
          )
          var allEffects: [Effect<Action>] = []
          if repositoriesChanged || wasRestoringSnapshot {
            allEffects.append(.send(.delegate(.repositoriesChanged(state.repositories))))
          }
          if selectionChanged {
            allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
          }
          if applyResult.didPrunePinned {
            let pinnedWorktreeIDs = state.pinnedWorktreeIDs
            allEffects.append(
              .run { _ in
                await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
              })
          }
          if applyResult.didPruneRepositoryOrder {
            let repositoryOrderIDs = state.repositoryOrderIDs
            allEffects.append(
              .run { _ in
                await repositoryPersistence.saveRepositoryOrderIDs(repositoryOrderIDs)
              })
          }
          if applyResult.didPruneWorktreeOrder {
            let worktreeOrderByRepository = state.worktreeOrderByRepository
            allEffects.append(
              .run { _ in
                await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
              })
          }
          if applyResult.didPruneArchivedWorktrees {
            let archivedWorktrees = state.archivedWorktrees
            allEffects.append(
              .run { _ in
                await repositoryPersistence.saveArchivedWorktrees(archivedWorktrees)
              }
            )
          }
          if failures.isEmpty, !wasRestoringSnapshot {
            let repositories = Array(state.repositories)
            allEffects.append(
              .run { _ in
                await repositoryPersistence.saveRepositorySnapshot(repositories)
              }
            )
          }
          if state.archivedAutoDeletePeriod != nil {
            allEffects.append(.send(.autoDeleteExpiredArchivedWorktrees))
          }
          return .merge(allEffects)

        case .selectArchivedWorktrees:
          state.selection = .archivedWorktrees
          state.sidebarSelectedWorktreeIDs = []
          return .send(.delegate(.selectedWorktreeChanged(nil)))

        case .selectCanvas:
          // Remember the current worktree so toggleCanvas can restore it.
          state.preCanvasWorktreeID = state.selectedWorktreeID
          state.preCanvasTerminalTargetID = state.selectedTerminalWorktree?.id
          state.selection = .canvas
          state.sidebarSelectedWorktreeIDs = []
          return .run { _ in
            await terminalClient.send(.setCanvasMode(true))
          }

        case .toggleCanvas:
          if state.isShowingCanvas {
            // Exit canvas: prefer the card focused in canvas, then the worktree
            // we came from, then the first available worktree.
            let targetID =
              terminalClient.canvasFocusedWorktreeID()
              ?? state.preCanvasTerminalTargetID
              ?? state.preCanvasWorktreeID
              ?? state.lastFocusedWorktreeID
              ?? state.orderedWorktreeRows().first?.id
            guard let targetID else { return .none }
            if state.worktree(for: targetID) == nil,
              let repository = state.repositories[id: targetID],
              repository.kind == .plain
            {
              state.pendingTerminalFocusWorktreeIDs.insert(targetID)
              return .send(.selectRepository(targetID))
            }
            return .send(.selectWorktree(targetID, focusTerminal: true))
          } else {
            // Enter canvas if there are any open worktrees.
            guard !state.orderedWorktreeRows().isEmpty else { return .none }
            return .send(.selectCanvas)
          }

        case .setSidebarSelectedWorktreeIDs(let worktreeIDs):
          let validWorktreeIDs = Set(state.orderedWorktreeRows().map(\.id))
          var nextWorktreeIDs = worktreeIDs.intersection(validWorktreeIDs)
          if let selectedWorktreeID = state.selectedWorktreeID, validWorktreeIDs.contains(selectedWorktreeID) {
            nextWorktreeIDs.insert(selectedWorktreeID)
          }
          state.sidebarSelectedWorktreeIDs = nextWorktreeIDs
          return .none

        case .selectRepository(let repositoryID):
          guard let repositoryID, state.repositories[id: repositoryID] != nil else { return .none }
          state.selection = .repository(repositoryID)
          state.sidebarSelectedWorktreeIDs = []
          return .send(.delegate(.selectedWorktreeChanged(state.selectedTerminalWorktree)))

        case .selectWorktree(let worktreeID, let focusTerminal):
          setSingleWorktreeSelection(worktreeID, state: &state)
          if focusTerminal, let worktreeID {
            state.pendingTerminalFocusWorktreeIDs.insert(worktreeID)
          }
          let selectedWorktree = state.worktree(for: worktreeID)
          return .send(.delegate(.selectedWorktreeChanged(selectedWorktree)))

        case .selectNextWorktree:
          guard let id = state.worktreeID(byOffset: 1) else { return .none }
          return .send(.selectWorktree(id))

        case .selectPreviousWorktree:
          guard let id = state.worktreeID(byOffset: -1) else { return .none }
          return .send(.selectWorktree(id))

        case .requestRenameBranch(let worktreeID, let branchName):
          guard let worktree = state.worktree(for: worktreeID) else { return .none }
          let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            state.alert = messageAlert(
              title: "Branch name required",
              message: "Enter a branch name to rename."
            )
            return .none
          }
          guard !trimmed.contains(where: \.isWhitespace) else {
            state.alert = messageAlert(
              title: "Branch name invalid",
              message: "Branch names can't contain spaces."
            )
            return .none
          }
          if trimmed == worktree.name {
            return .none
          }
          analyticsClient.capture("branch_renamed", nil)
          return .run { send in
            do {
              try await gitClient.renameBranch(worktree.workingDirectory, trimmed)
              await send(.reloadRepositories(animated: true))
            } catch {
              await send(
                .presentAlert(
                  title: "Unable to rename branch",
                  message: error.localizedDescription
                )
              )
            }
          }

        case .worktreeCreationPrompt(.presented(.delegate(.cancel))):
          return .send(.worktreeCreation(.promptCanceled))

        case .worktreeCreationPrompt(
          .presented(.delegate(.submit(let repositoryID, let branchName, let baseRef)))
        ):
          return .send(
            .worktreeCreation(
              .startPromptedWorktreeCreation(
                repositoryID: repositoryID,
                branchName: branchName,
                baseRef: baseRef
              )
            )
          )

        case .worktreeCreationPrompt(.dismiss):
          return .send(.worktreeCreation(.promptDismissed))

        case .worktreeCreationPrompt:
          return .none

        case .alert(.presented(.confirmArchiveWorktree(let worktreeID, let repositoryID))):
          return .send(.worktreeLifecycle(.archiveWorktreeConfirmed(worktreeID, repositoryID)))

        case .alert(.presented(.confirmArchiveWorktrees(let targets))):
          return .merge(
            targets.map { target in
              .send(.worktreeLifecycle(.archiveWorktreeConfirmed(target.worktreeID, target.repositoryID)))
            }
          )

        case .alert(.presented(.confirmDeleteWorktree(let worktreeID, let repositoryID))):
          return .send(.worktreeLifecycle(.deleteWorktreeConfirmed(worktreeID, repositoryID)))

        case .alert(.presented(.confirmDeleteWorktrees(let targets))):
          return .merge(
            targets.map { target in
              .send(.worktreeLifecycle(.deleteWorktreeConfirmed(target.worktreeID, target.repositoryID)))
            }
          )

        case .alert(.presented(.confirmRemoveRepository(let repositoryID))):
          guard let repository = state.repositories[id: repositoryID] else {
            return .none
          }
          if state.removingRepositoryIDs.contains(repository.id) {
            return .none
          }
          state.alert = nil
          state.removingRepositoryIDs.insert(repository.id)
          let selectionWasRemoved =
            state.selectedWorktreeID.map { id in
              repository.worktrees.contains(where: { $0.id == id })
            } ?? false
          return .send(
            .repositoryManagement(.repositoryRemoved(repository.id, selectionWasRemoved: selectionWasRemoved)))

        case .presentAlert(let title, let message):
          state.alert = messageAlert(title: title, message: message)
          return .none

        case .showToast(let toast):
          state.statusToast = toast
          switch toast {
          case .inProgress:
            return .cancel(id: CancelID.toastAutoDismiss)
          case .success, .warning:
            return .run { send in
              try? await ContinuousClock().sleep(for: .seconds(2.5))
              await send(.dismissToast)
            }
            .cancellable(id: CancelID.toastAutoDismiss, cancelInFlight: true)
          }

        case .dismissToast:
          state.statusToast = nil
          return .none

        case .worktreeInfoEvent(let event):
          switch event {
          case .branchChanged(let worktreeID):
            guard let worktree = state.worktree(for: worktreeID) else {
              return .none
            }
            let worktreeURL = worktree.workingDirectory
            let gitClient = gitClient
            return .run { send in
              if let name = await gitClient.branchName(worktreeURL) {
                await send(.worktreeBranchNameLoaded(worktreeID: worktreeID, name: name))
              }
            }
          case .filesChanged(let worktreeID):
            guard let worktree = state.worktree(for: worktreeID) else {
              return .none
            }
            let worktreeURL = worktree.workingDirectory
            let gitClient = gitClient
            return .run { send in
              if let changes = await gitClient.lineChanges(worktreeURL) {
                await send(
                  .worktreeLineChangesLoaded(
                    worktreeID: worktreeID,
                    added: changes.added,
                    removed: changes.removed
                  )
                )
              }
            }
          case .repositoryPullRequestRefresh(let repositoryRootURL, let worktreeIDs):
            return .send(
              .githubIntegration(
                .repositoryPullRequestRefreshRequested(
                  repositoryRootURL: repositoryRootURL,
                  worktreeIDs: worktreeIDs
                )
              )
            )
          }

        case .worktreeBranchNameLoaded(let worktreeID, let name):
          updateWorktreeName(worktreeID, name: name, state: &state)
          return .none

        case .worktreeLineChangesLoaded(let worktreeID, let added, let removed):
          updateWorktreeLineChanges(
            worktreeID: worktreeID,
            added: added,
            removed: removed,
            state: &state
          )
          return .none

        case .alert(.dismiss):
          state.alert = nil
          return .none

        case .alert:
          return .none

        case .delegate:
          return .none
        }
      }

      worktreeCreationReducer
      worktreeLifecycleReducer
      worktreeOrderingReducer
      githubIntegrationReducer
      repositoryManagementReducer
    }
    .ifLet(\.$worktreeCreationPrompt, action: \.worktreeCreationPrompt) {
      WorktreeCreationPromptFeature()
    }
  }

  func refreshRepositoryPullRequests(
    repositoryID: Repository.ID,
    repositoryRootURL: URL,
    worktrees: [Worktree],
    branches: [String]
  ) -> Effect<Action> {
    let gitClient = gitClient
    let githubCLI = githubCLI
    return .run { send in
      guard let remoteInfo = await gitClient.remoteInfo(repositoryRootURL) else {
        await send(.githubIntegration(.repositoryPullRequestRefreshCompleted(repositoryID)))
        return
      }
      do {
        let prsByBranch = try await githubCLI.batchPullRequests(
          remoteInfo.host,
          remoteInfo.owner,
          remoteInfo.repo,
          branches
        )
        var pullRequestsByWorktreeID: [Worktree.ID: GithubPullRequest?] = [:]
        for worktree in worktrees {
          pullRequestsByWorktreeID[worktree.id] = prsByBranch[worktree.name]
        }
        await send(
          .githubIntegration(
            .repositoryPullRequestsLoaded(
              repositoryID: repositoryID,
              pullRequestsByWorktreeID: pullRequestsByWorktreeID
            )
          )
        )
      } catch {
        await send(.githubIntegration(.repositoryPullRequestRefreshCompleted(repositoryID)))
        return
      }
      await send(.githubIntegration(.repositoryPullRequestRefreshCompleted(repositoryID)))
    }
  }

  func loadPersistedRepositoryEntries(
    fallbackRoots: [URL] = []
  ) async -> [PersistedRepositoryEntry] {
    let entries = await repositoryPersistence.loadRepositoryEntries()
    let resolvedEntries: [PersistedRepositoryEntry]
    if !entries.isEmpty {
      resolvedEntries = entries
    } else {
      let loadedPaths = await repositoryPersistence.loadRoots()
      let pathSource =
        if !loadedPaths.isEmpty {
          loadedPaths
        } else {
          fallbackRoots.map { $0.path(percentEncoded: false) }
        }
      resolvedEntries = RepositoryEntryNormalizer.normalize(
        pathSource.map { PersistedRepositoryEntry(path: $0, kind: .git) }
      )
    }
    return await upgradedRepositoryEntriesIfNeeded(resolvedEntries)
  }

  func upgradedRepositoryEntriesIfNeeded(
    _ entries: [PersistedRepositoryEntry]
  ) async -> [PersistedRepositoryEntry] {
    let upgradedEntries = await withTaskGroup(of: (Int, PersistedRepositoryEntry).self) { group in
      for (index, entry) in entries.enumerated() {
        let gitClient = self.gitClient
        group.addTask {
          let normalizedPath = URL(fileURLWithPath: entry.path)
            .standardizedFileURL
            .path(percentEncoded: false)
          do {
            let repoRoot = try await gitClient.repoRoot(URL(fileURLWithPath: normalizedPath))
            let normalizedRepoRoot = repoRoot.standardizedFileURL.path(percentEncoded: false)
            switch entry.kind {
            case .plain:
              if normalizedRepoRoot == normalizedPath {
                return (index, PersistedRepositoryEntry(path: normalizedPath, kind: .git))
              }
              return (index, PersistedRepositoryEntry(path: normalizedPath, kind: .plain))
            case .git:
              if normalizedRepoRoot == normalizedPath {
                return (index, PersistedRepositoryEntry(path: normalizedPath, kind: .git))
              }
              return (index, PersistedRepositoryEntry(path: normalizedPath, kind: .plain))
            }
          } catch {
            if entry.kind == .git,
              Self.isNotGitRepositoryError(error),
              FileManager.default.fileExists(atPath: normalizedPath)
            {
              return (index, PersistedRepositoryEntry(path: normalizedPath, kind: .plain))
            }
          }
          return (index, PersistedRepositoryEntry(path: normalizedPath, kind: entry.kind))
        }
      }

      var results = [PersistedRepositoryEntry?](repeating: nil, count: entries.count)
      for await (index, entry) in group {
        results[index] = entry
      }
      return results.compactMap { $0 }
    }

    let normalizedEntries = RepositoryEntryNormalizer.normalize(upgradedEntries)
    if normalizedEntries != entries {
      await repositoryPersistence.saveRepositoryEntries(normalizedEntries)
    }
    return normalizedEntries
  }

  nonisolated static func isNotGitRepositoryError(_ error: any Error) -> Bool {
    guard case GitClientError.commandFailed(_, let message) = error else {
      return false
    }
    return message.localizedCaseInsensitiveContains("not a git repository")
  }

  nonisolated static func openRepositoryFailureMessage(path: String, error: any Error) -> String {
    let detail: String
    if case GitClientError.commandFailed(_, let message) = error,
      !message.isEmpty
    {
      detail = message
    } else {
      detail = error.localizedDescription
    }
    return "\(path): \(detail)"
  }

  func loadRepositories(
    fallbackRoots: [URL] = [],
    animated: Bool = false
  ) -> Effect<Action> {
    let gitClient = gitClient
    return .run { [animated, fallbackRoots] send in
      let entries = await loadPersistedRepositoryEntries(fallbackRoots: fallbackRoots)
      let roots = entries.map { URL(fileURLWithPath: $0.path) }
      for entry in entries where entry.kind == .git {
        _ = try? await gitClient.pruneWorktrees(URL(fileURLWithPath: entry.path))
      }
      let (repositories, failures) = await loadRepositoriesData(entries)
      await send(
        .repositoriesLoaded(
          repositories,
          failures: failures,
          roots: roots,
          animated: animated
        )
      )
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private struct WorktreesFetchResult: Sendable {
    let entry: PersistedRepositoryEntry
    let repository: Repository?
    let errorMessage: String?
  }

  func loadRepositoriesData(_ entries: [PersistedRepositoryEntry]) async -> ([Repository], [LoadFailure]) {
    let fetchResults = await withTaskGroup(of: WorktreesFetchResult.self) { group in
      for entry in entries {
        let gitClient = self.gitClient
        group.addTask {
          let rootURL = URL(fileURLWithPath: entry.path).standardizedFileURL
          switch entry.kind {
          case .git:
            do {
              let worktrees = try await gitClient.worktrees(rootURL)
              return WorktreesFetchResult(
                entry: entry,
                repository: Repository(
                  id: rootURL.path(percentEncoded: false),
                  rootURL: rootURL,
                  name: Repository.name(for: rootURL),
                  kind: .git,
                  worktrees: IdentifiedArray(uniqueElements: worktrees)
                ),
                errorMessage: nil
              )
            } catch {
              return WorktreesFetchResult(
                entry: entry,
                repository: nil,
                errorMessage: error.localizedDescription
              )
            }
          case .plain:
            return WorktreesFetchResult(
              entry: entry,
              repository: Repository(
                id: rootURL.path(percentEncoded: false),
                rootURL: rootURL,
                name: Repository.name(for: rootURL),
                kind: .plain,
                worktrees: IdentifiedArray()
              ),
              errorMessage: nil
            )
          }
        }
      }

      var resultsByRootID: [Repository.ID: WorktreesFetchResult] = [:]
      for await result in group {
        let rootID = URL(fileURLWithPath: result.entry.path).standardizedFileURL.path(percentEncoded: false)
        resultsByRootID[rootID] = result
      }
      return resultsByRootID
    }

    var loaded: [Repository] = []
    var failures: [LoadFailure] = []
    for entry in entries {
      let normalizedRoot = URL(fileURLWithPath: entry.path).standardizedFileURL
      let rootID = normalizedRoot.path(percentEncoded: false)
      guard let result = fetchResults[rootID] else { continue }
      if let repository = result.repository {
        loaded.append(repository)
      } else {
        failures.append(
          LoadFailure(
            rootID: rootID,
            message: result.errorMessage ?? "Unknown error"
          )
        )
      }
    }
    return (loaded, failures)
  }

  func applyRepositories(
    _ repositories: [Repository],
    roots: [URL],
    shouldPruneArchivedWorktrees: Bool,
    state: inout State,
    animated: Bool
  ) -> ApplyRepositoriesResult {
    let previousCounts = Dictionary(
      uniqueKeysWithValues: state.repositories.map { ($0.id, $0.worktrees.count) }
    )
    let repositoryIDs = Set(repositories.map(\.id))
    let newCounts = Dictionary(
      uniqueKeysWithValues: repositories.map { ($0.id, $0.worktrees.count) }
    )
    var addedCounts: [Repository.ID: Int] = [:]
    for (id, newCount) in newCounts {
      let oldCount = previousCounts[id] ?? 0
      let added = newCount - oldCount
      if added > 0 {
        addedCounts[id] = added
      }
    }
    let filteredPendingWorktrees = state.pendingWorktrees.filter { pending in
      guard repositoryIDs.contains(pending.repositoryID) else { return false }
      guard let remaining = addedCounts[pending.repositoryID], remaining > 0 else { return true }
      addedCounts[pending.repositoryID] = remaining - 1
      return false
    }
    let availableWorktreeIDs = Set(repositories.flatMap { $0.worktrees.map(\.id) })
    let filteredDeletingIDs = state.deletingWorktreeIDs.intersection(availableWorktreeIDs)
    let filteredSetupScriptIDs = state.pendingSetupScriptWorktreeIDs.filter {
      availableWorktreeIDs.contains($0)
    }
    let filteredFocusIDs = state.pendingTerminalFocusWorktreeIDs.filter {
      availableWorktreeIDs.contains($0)
    }
    let filteredArchivingIDs = state.archivingWorktreeIDs
    let filteredArchiveScriptProgress = state.archiveScriptProgressByWorktreeID.filter {
      availableWorktreeIDs.contains($0.key) || filteredArchivingIDs.contains($0.key)
    }
    let filteredWorktreeInfo = state.worktreeInfoByID.filter {
      availableWorktreeIDs.contains($0.key)
    }
    let identifiedRepositories = IdentifiedArray(uniqueElements: repositories)
    if animated {
      withAnimation {
        state.repositories = identifiedRepositories
        state.pendingWorktrees = filteredPendingWorktrees
        state.deletingWorktreeIDs = filteredDeletingIDs
        state.pendingSetupScriptWorktreeIDs = filteredSetupScriptIDs
        state.pendingTerminalFocusWorktreeIDs = filteredFocusIDs
        state.archivingWorktreeIDs = filteredArchivingIDs
        state.archiveScriptProgressByWorktreeID = filteredArchiveScriptProgress
        state.worktreeInfoByID = filteredWorktreeInfo
      }
    } else {
      state.repositories = identifiedRepositories
      state.pendingWorktrees = filteredPendingWorktrees
      state.deletingWorktreeIDs = filteredDeletingIDs
      state.pendingSetupScriptWorktreeIDs = filteredSetupScriptIDs
      state.pendingTerminalFocusWorktreeIDs = filteredFocusIDs
      state.archivingWorktreeIDs = filteredArchivingIDs
      state.archiveScriptProgressByWorktreeID = filteredArchiveScriptProgress
      state.worktreeInfoByID = filteredWorktreeInfo
    }
    let didPrunePinned = prunePinnedWorktreeIDs(state: &state)
    let didPruneRepositoryOrder = pruneRepositoryOrderIDs(roots: roots, state: &state)
    let didPruneWorktreeOrder = pruneWorktreeOrderByRepository(roots: roots, state: &state)
    let didPruneArchivedWorktrees =
      shouldPruneArchivedWorktrees
      ? pruneArchivedWorktrees(availableWorktreeIDs: availableWorktreeIDs, state: &state)
      : false
    if !state.isShowingArchivedWorktrees, !state.isShowingCanvas,
      !isSidebarSelectionValid(state.selection, state: state)
    {
      state.selection = nil
    }
    if state.shouldRestoreLastFocusedWorktree {
      state.shouldRestoreLastFocusedWorktree = false
      if state.selection == nil,
        isSelectionValid(state.lastFocusedWorktreeID, state: state)
      {
        state.selection = state.lastFocusedWorktreeID.map(SidebarSelection.worktree)
      }
    }
    if state.selection == nil, state.shouldSelectFirstAfterReload {
      state.selection = firstAvailableWorktreeID(from: repositories, state: state)
        .map(SidebarSelection.worktree)
      state.shouldSelectFirstAfterReload = false
    }
    return ApplyRepositoriesResult(
      didPrunePinned: didPrunePinned,
      didPruneRepositoryOrder: didPruneRepositoryOrder,
      didPruneWorktreeOrder: didPruneWorktreeOrder,
      didPruneArchivedWorktrees: didPruneArchivedWorktrees
    )
  }

  func messageAlert(title: String, message: String) -> AlertState<Alert> {
    AlertState {
      TextState(title)
    } actions: {
      ButtonState(role: .cancel) {
        TextState("OK")
      }
    } message: {
      TextState(message)
    }
  }

  func confirmationAlertForRepositoryRemoval(
    repositoryID: Repository.ID,
    state: State
  ) -> AlertState<Alert>? {
    guard let repository = state.repositories[id: repositoryID] else {
      return nil
    }
    return AlertState {
      TextState("Remove repository?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmRemoveRepository(repository.id)) {
        TextState("Remove repository")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "This removes the repository from Prowl. "
          + "Worktrees and the main repository folder stay on disk."
      )
    }
  }

  func selectionDidChange(
    previousSelectionID: Worktree.ID?,
    previousSelectedWorktree: Worktree?,
    selectedWorktreeID: Worktree.ID?,
    selectedWorktree: Worktree?
  ) -> Bool {
    if previousSelectionID != selectedWorktreeID {
      return true
    }
    if previousSelectedWorktree?.workingDirectory != selectedWorktree?.workingDirectory {
      return true
    }
    if previousSelectedWorktree?.repositoryRootURL != selectedWorktree?.repositoryRootURL {
      return true
    }
    return false
  }
}

// Sub-reducers are in separate files:
// - RepositoriesFeature+WorktreeCreation.swift
// - RepositoriesFeature+WorktreeLifecycle.swift
// - RepositoriesFeature+WorktreeOrdering.swift
// - RepositoriesFeature+GithubIntegration.swift
// - RepositoriesFeature+RepositoryManagement.swift

extension RepositoriesFeature.State {
  var selectedWorktreeID: Worktree.ID? {
    selection?.worktreeID
  }

  var selectedRepositoryID: Repository.ID? {
    guard case .repository(let repositoryID) = selection else { return nil }
    return repositoryID
  }

  var selectedRepository: Repository? {
    guard let selectedRepositoryID else { return nil }
    return repositories[id: selectedRepositoryID]
  }

  var selectedTerminalWorktree: Worktree? {
    if let selectedWorktreeID {
      return worktree(for: selectedWorktreeID)
    }
    guard let selectedRepository,
      selectedRepository.capabilities.supportsRunnableFolderActions,
      !selectedRepository.capabilities.supportsWorktrees
    else {
      return nil
    }
    return Worktree(
      id: selectedRepository.id,
      name: selectedRepository.name,
      detail: selectedRepository.rootURL.path(percentEncoded: false),
      workingDirectory: selectedRepository.rootURL,
      repositoryRootURL: selectedRepository.rootURL
    )
  }

  var terminalStateIDs: Set<Worktree.ID> {
    Set(
      repositories.flatMap { repository -> [Worktree.ID] in
        if repository.capabilities.supportsWorktrees {
          repository.worktrees.map(\.id)
        } else if repository.capabilities.supportsRunnableFolderActions {
          [repository.id]
        } else {
          []
        }
      }
    )
  }

  var expandedRepositoryIDs: Set<Repository.ID> {
    let repositoryIDs = Set(repositories.map(\.id))
    let collapsedSet = Set(collapsedRepositoryIDs).intersection(repositoryIDs)
    let pendingRepositoryIDs = Set(pendingWorktrees.map(\.repositoryID))
    return repositoryIDs.subtracting(collapsedSet).union(pendingRepositoryIDs)
  }

  func worktreeID(byOffset offset: Int) -> Worktree.ID? {
    let rows = orderedWorktreeRows(includingRepositoryIDs: expandedRepositoryIDs)
    guard !rows.isEmpty else { return nil }
    if let currentID = selectedWorktreeID,
      let currentIndex = rows.firstIndex(where: { $0.id == currentID })
    {
      return rows[(currentIndex + offset + rows.count) % rows.count].id
    }
    return rows[offset > 0 ? 0 : rows.count - 1].id
  }

  var isShowingArchivedWorktrees: Bool {
    selection == .archivedWorktrees
  }

  var isShowingCanvas: Bool {
    selection == .canvas
  }

  var archivedWorktreeIDSet: Set<Worktree.ID> {
    Set(archivedWorktrees.map(\.id))
  }

  func isWorktreeArchived(_ id: Worktree.ID) -> Bool {
    archivedWorktreeIDSet.contains(id)
  }

  func worktreeInfo(for worktreeID: Worktree.ID) -> WorktreeInfoEntry? {
    worktreeInfoByID[worktreeID]
  }

  func worktreesForInfoWatcher() -> [Worktree] {
    let worktrees = repositories.flatMap(\.worktrees)
    guard !isShowingArchivedWorktrees else {
      return worktrees
    }
    let archivedSet = archivedWorktreeIDSet
    return worktrees.filter { !archivedSet.contains($0.id) }
  }

  func archivedWorktreesByRepository() -> [(repository: Repository, worktrees: [Worktree])] {
    let archivedSet = archivedWorktreeIDSet
    var groups: [(repository: Repository, worktrees: [Worktree])] = []
    for repository in repositories {
      let worktrees = Array(repository.worktrees.filter { archivedSet.contains($0.id) })
      if !worktrees.isEmpty {
        groups.append((repository: repository, worktrees: worktrees))
      }
    }
    return groups
  }

  var canCreateWorktree: Bool {
    if repositories.isEmpty {
      return false
    }
    if let repository = repositoryForWorktreeCreation(self) {
      return !removingRepositoryIDs.contains(repository.id)
    }
    return false
  }

  func worktree(for id: Worktree.ID?) -> Worktree? {
    guard let id else { return nil }
    for repository in repositories {
      if let worktree = repository.worktrees[id: id] {
        return worktree
      }
    }
    return nil
  }

  func pendingWorktree(for id: Worktree.ID?) -> PendingWorktree? {
    guard let id else { return nil }
    return pendingWorktrees.first(where: { $0.id == id })
  }

  func archiveScriptProgress(for id: Worktree.ID?) -> ArchiveScriptProgress? {
    guard let id else { return nil }
    return archiveScriptProgressByWorktreeID[id]
  }

  func shouldFocusTerminal(for worktreeID: Worktree.ID) -> Bool {
    pendingTerminalFocusWorktreeIDs.contains(worktreeID)
  }

  private func makePendingWorktreeRow(_ pending: PendingWorktree) -> WorktreeRowModel {
    let isDeleting = removingRepositoryIDs.contains(pending.repositoryID)
    return WorktreeRowModel(
      id: pending.id,
      repositoryID: pending.repositoryID,
      name: pending.progress.titleText,
      detail: pending.progress.detailText,
      info: worktreeInfo(for: pending.id),
      isPinned: false,
      isMainWorktree: false,
      isPending: true,
      isArchiving: false,
      isDeleting: isDeleting,
      isRemovable: false
    )
  }

  private func makeWorktreeRow(
    _ worktree: Worktree,
    repositoryID: Repository.ID,
    isPinned: Bool,
    isMainWorktree: Bool
  ) -> WorktreeRowModel {
    let isDeleting =
      removingRepositoryIDs.contains(repositoryID)
      || deletingWorktreeIDs.contains(worktree.id)
    let isArchiving = archivingWorktreeIDs.contains(worktree.id)
    return WorktreeRowModel(
      id: worktree.id,
      repositoryID: repositoryID,
      name: worktree.name,
      detail: worktree.detail,
      info: worktreeInfo(for: worktree.id),
      isPinned: isPinned,
      isMainWorktree: isMainWorktree,
      isPending: false,
      isArchiving: isArchiving,
      isDeleting: isDeleting,
      isRemovable: !isDeleting && !isArchiving
    )
  }

  func selectedRow(for id: Worktree.ID?) -> WorktreeRowModel? {
    guard let id else { return nil }
    if isWorktreeArchived(id) {
      return nil
    }
    if let pending = pendingWorktree(for: id) {
      return makePendingWorktreeRow(pending)
    }
    for repository in repositories {
      if let worktree = repository.worktrees[id: id] {
        return makeWorktreeRow(
          worktree,
          repositoryID: repository.id,
          isPinned: pinnedWorktreeIDs.contains(worktree.id),
          isMainWorktree: isMainWorktree(worktree)
        )
      }
    }
    return nil
  }

  func repositoryName(for id: Repository.ID) -> String? {
    repositories[id: id]?.name
  }

  func orderedRepositoryRoots() -> [URL] {
    let rootsByID = Dictionary(
      uniqueKeysWithValues: repositoryRoots.map {
        ($0.standardizedFileURL.path(percentEncoded: false), $0.standardizedFileURL)
      }
    )
    var ordered: [URL] = []
    var seen: Set<Repository.ID> = []
    for id in repositoryOrderIDs {
      if let rootURL = rootsByID[id], seen.insert(id).inserted {
        ordered.append(rootURL)
      }
    }
    for rootURL in repositoryRoots {
      let id = rootURL.standardizedFileURL.path(percentEncoded: false)
      if seen.insert(id).inserted {
        ordered.append(rootURL.standardizedFileURL)
      }
    }
    if ordered.isEmpty {
      ordered = repositories.map(\.rootURL)
    }
    return ordered
  }

  func orderedRepositoryIDs() -> [Repository.ID] {
    orderedRepositoryRoots().map { $0.standardizedFileURL.path(percentEncoded: false) }
  }

  func repositoryID(for worktreeID: Worktree.ID?) -> Repository.ID? {
    selectedRow(for: worktreeID)?.repositoryID
  }

  func repositoryID(containing worktreeID: Worktree.ID) -> Repository.ID? {
    for repository in repositories where repository.worktrees[id: worktreeID] != nil {
      return repository.id
    }
    return nil
  }

  func isMainWorktree(_ worktree: Worktree) -> Bool {
    worktree.workingDirectory.standardizedFileURL == worktree.repositoryRootURL.standardizedFileURL
  }

  func isWorktreeMerged(_ worktree: Worktree) -> Bool {
    worktreeInfoByID[worktree.id]?.pullRequest?.state == "MERGED"
  }

  func orderedPinnedWorktreeIDs(in repository: Repository) -> [Worktree.ID] {
    let archivedSet = archivedWorktreeIDSet
    return pinnedWorktreeIDs.filter { id in
      if archivedSet.contains(id) {
        return false
      }
      if let worktree = repository.worktrees[id: id] {
        return !isMainWorktree(worktree)
      }
      return false
    }
  }

  func orderedPinnedWorktrees(in repository: Repository) -> [Worktree] {
    orderedPinnedWorktreeIDs(in: repository).compactMap { repository.worktrees[id: $0] }
  }

  func replacingPinnedWorktreeIDs(
    in repository: Repository,
    with reordered: [Worktree.ID]
  ) -> [Worktree.ID] {
    let repoPinnedIDs = Set(orderedPinnedWorktreeIDs(in: repository))
    var iterator = reordered.makeIterator()
    return pinnedWorktreeIDs.map { id in
      if repoPinnedIDs.contains(id) {
        return iterator.next() ?? id
      }
      return id
    }
  }

  func orderedUnpinnedWorktreeIDs(in repository: Repository) -> [Worktree.ID] {
    let mainID = repository.worktrees.first(where: { isMainWorktree($0) })?.id
    let pinnedSet = Set(pinnedWorktreeIDs)
    let archivedSet = archivedWorktreeIDSet
    let available = repository.worktrees.filter { worktree in
      worktree.id != mainID
        && !pinnedSet.contains(worktree.id)
        && !archivedSet.contains(worktree.id)
    }
    let orderedIDs = worktreeOrderByRepository[repository.id] ?? []
    let availableIDs = Set(available.map(\.id))
    let orderedIDSet = Set(orderedIDs)
    var seen: Set<Worktree.ID> = []
    var missing: [Worktree.ID] = []
    for worktree in available where !orderedIDSet.contains(worktree.id) {
      if seen.insert(worktree.id).inserted {
        missing.append(worktree.id)
      }
    }
    var ordered: [Worktree.ID] = []
    for id in orderedIDs {
      if availableIDs.contains(id),
        seen.insert(id).inserted
      {
        ordered.append(id)
      }
    }
    return missing + ordered
  }

  func orderedUnpinnedWorktrees(in repository: Repository) -> [Worktree] {
    orderedUnpinnedWorktreeIDs(in: repository).compactMap { repository.worktrees[id: $0] }
  }

  func orderedWorktrees(in repository: Repository) -> [Worktree] {
    var ordered: [Worktree] = []
    if let mainWorktree = repository.worktrees.first(where: { isMainWorktree($0) }) {
      if !isWorktreeArchived(mainWorktree.id) {
        ordered.append(mainWorktree)
      }
    }
    ordered.append(contentsOf: orderedPinnedWorktrees(in: repository))
    ordered.append(contentsOf: orderedUnpinnedWorktrees(in: repository))
    return ordered
  }

  func isWorktreePinned(_ worktree: Worktree) -> Bool {
    pinnedWorktreeIDs.contains(worktree.id)
  }

  var confirmWorktreeAlert: RepositoriesFeature.Alert? {
    guard let alert else { return nil }
    for button in alert.buttons {
      if case .confirmArchiveWorktree(let worktreeID, let repositoryID)? = button.action.action {
        return .confirmArchiveWorktree(worktreeID, repositoryID)
      }
      if case .confirmArchiveWorktrees(let targets)? = button.action.action {
        return .confirmArchiveWorktrees(targets)
      }
      if case .confirmDeleteWorktree(let worktreeID, let repositoryID)? = button.action.action {
        return .confirmDeleteWorktree(worktreeID, repositoryID)
      }
      if case .confirmDeleteWorktrees(let targets)? = button.action.action {
        return .confirmDeleteWorktrees(targets)
      }
    }
    return nil
  }

  func isRemovingRepository(_ repository: Repository) -> Bool {
    removingRepositoryIDs.contains(repository.id)
  }

  func worktreeRowSections(in repository: Repository) -> WorktreeRowSections {
    let mainWorktree = repository.worktrees.first(where: { isMainWorktree($0) })
    let pinnedWorktrees = orderedPinnedWorktrees(in: repository)
    let unpinnedWorktrees = orderedUnpinnedWorktrees(in: repository)
    let pendingEntries = pendingWorktrees.filter { $0.repositoryID == repository.id }
    let mainRow: WorktreeRowModel? =
      if let mainWorktree, !isWorktreeArchived(mainWorktree.id) {
        makeWorktreeRow(
          mainWorktree,
          repositoryID: repository.id,
          isPinned: false,
          isMainWorktree: true
        )
      } else {
        nil
      }
    var pinnedRows: [WorktreeRowModel] = []
    for worktree in pinnedWorktrees {
      pinnedRows.append(
        makeWorktreeRow(
          worktree,
          repositoryID: repository.id,
          isPinned: true,
          isMainWorktree: false
        )
      )
    }
    var pendingRows: [WorktreeRowModel] = []
    for pending in pendingEntries {
      pendingRows.append(makePendingWorktreeRow(pending))
    }
    var unpinnedRows: [WorktreeRowModel] = []
    for worktree in unpinnedWorktrees {
      unpinnedRows.append(
        makeWorktreeRow(
          worktree,
          repositoryID: repository.id,
          isPinned: false,
          isMainWorktree: false
        )
      )
    }
    return WorktreeRowSections(
      main: mainRow,
      pinned: pinnedRows,
      pending: pendingRows,
      unpinned: unpinnedRows
    )
  }

  func worktreeRows(in repository: Repository) -> [WorktreeRowModel] {
    let sections = worktreeRowSections(in: repository)
    return sections.allRows
  }

  func orderedWorktreeRows() -> [WorktreeRowModel] {
    orderedWorktreeRows(includingRepositoryIDs: Set(repositories.map(\.id)))
  }

  func orderedWorktreeRows(includingRepositoryIDs: Set<Repository.ID>) -> [WorktreeRowModel] {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    return orderedRepositoryIDs()
      .filter { includingRepositoryIDs.contains($0) }
      .compactMap { repositoriesByID[$0] }
      .flatMap { worktreeRows(in: $0) }
  }
}

struct WorktreeRowSections {
  let main: WorktreeRowModel?
  let pinned: [WorktreeRowModel]
  let pending: [WorktreeRowModel]
  let unpinned: [WorktreeRowModel]

  var allRows: [WorktreeRowModel] {
    var rows: [WorktreeRowModel] = []
    if let main {
      rows.append(main)
    }
    rows.append(contentsOf: pinned)
    rows.append(contentsOf: pending)
    rows.append(contentsOf: unpinned)
    return rows
  }
}

struct FailedWorktreeCleanup {
  let didRemoveWorktree: Bool
  let didUpdatePinned: Bool
  let didUpdateOrder: Bool
  let worktree: Worktree?
}

func removePendingWorktree(_ id: String, state: inout RepositoriesFeature.State) {
  state.pendingWorktrees.removeAll { $0.id == id }
}

func updatePendingWorktreeProgress(
  _ id: String,
  progress: WorktreeCreationProgress,
  state: inout RepositoriesFeature.State
) {
  guard let index = state.pendingWorktrees.firstIndex(where: { $0.id == id }) else {
    return
  }
  state.pendingWorktrees[index].progress = progress
}

func insertWorktree(
  _ worktree: Worktree,
  repositoryID: Repository.ID,
  state: inout RepositoriesFeature.State
) {
  guard let index = state.repositories.index(id: repositoryID) else { return }
  let repository = state.repositories[index]
  if repository.worktrees[id: worktree.id] != nil {
    return
  }
  var worktrees = repository.worktrees
  worktrees.insert(worktree, at: 0)
  state.repositories[index] = Repository(
    id: repository.id,
    rootURL: repository.rootURL,
    name: repository.name,
    worktrees: worktrees
  )
}

@discardableResult
func removeWorktree(
  _ worktreeID: Worktree.ID,
  repositoryID: Repository.ID,
  state: inout RepositoriesFeature.State
) -> Bool {
  guard let index = state.repositories.index(id: repositoryID) else { return false }
  let repository = state.repositories[index]
  guard repository.worktrees[id: worktreeID] != nil else { return false }
  var worktrees = repository.worktrees
  worktrees.remove(id: worktreeID)
  state.repositories[index] = Repository(
    id: repository.id,
    rootURL: repository.rootURL,
    name: repository.name,
    worktrees: worktrees
  )
  return true
}

func cleanupFailedWorktree(
  repositoryID: Repository.ID,
  name: String?,
  baseDirectory: URL,
  state: inout RepositoriesFeature.State
) -> FailedWorktreeCleanup {
  guard let name, !name.isEmpty else {
    return FailedWorktreeCleanup(
      didRemoveWorktree: false,
      didUpdatePinned: false,
      didUpdateOrder: false,
      worktree: nil
    )
  }
  let repositoryRootURL = URL(fileURLWithPath: repositoryID).standardizedFileURL
  let normalizedBaseDirectory = baseDirectory.standardizedFileURL
  let worktreeURL =
    normalizedBaseDirectory
    .appending(path: name, directoryHint: .isDirectory)
    .standardizedFileURL
  guard isPathInsideBaseDirectory(worktreeURL, baseDirectory: normalizedBaseDirectory) else {
    return FailedWorktreeCleanup(
      didRemoveWorktree: false,
      didUpdatePinned: false,
      didUpdateOrder: false,
      worktree: nil
    )
  }
  let worktreeID = worktreeURL.path(percentEncoded: false)
  let worktree =
    state.repositories[id: repositoryID]?.worktrees[id: worktreeID]
    ?? Worktree(
      id: worktreeID,
      name: name,
      detail: "",
      workingDirectory: worktreeURL,
      repositoryRootURL: repositoryRootURL
    )
  let cleanup = cleanupWorktreeState(
    worktreeID,
    repositoryID: repositoryID,
    state: &state
  )
  return FailedWorktreeCleanup(
    didRemoveWorktree: cleanup.didRemoveWorktree,
    didUpdatePinned: cleanup.didUpdatePinned,
    didUpdateOrder: cleanup.didUpdateOrder,
    worktree: worktree
  )
}

func isPathInsideBaseDirectory(_ path: URL, baseDirectory: URL) -> Bool {
  PathPolicy.contains(path, in: baseDirectory)
}

struct WorktreeCleanupStateResult {
  let didRemoveWorktree: Bool
  let didUpdatePinned: Bool
  let didUpdateOrder: Bool
}

func cleanupWorktreeState(
  _ worktreeID: Worktree.ID,
  repositoryID: Repository.ID,
  state: inout RepositoriesFeature.State
) -> WorktreeCleanupStateResult {
  let didRemoveWorktree = removeWorktree(worktreeID, repositoryID: repositoryID, state: &state)
  state.pendingWorktrees.removeAll { $0.id == worktreeID }
  state.pendingSetupScriptWorktreeIDs.remove(worktreeID)
  state.pendingTerminalFocusWorktreeIDs.remove(worktreeID)
  state.archivingWorktreeIDs.remove(worktreeID)
  state.archiveScriptProgressByWorktreeID.removeValue(forKey: worktreeID)
  state.deletingWorktreeIDs.remove(worktreeID)
  state.worktreeInfoByID.removeValue(forKey: worktreeID)
  let didUpdatePinned = state.pinnedWorktreeIDs.contains(worktreeID)
  if didUpdatePinned {
    state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
  }
  var didUpdateOrder = false
  if var order = state.worktreeOrderByRepository[repositoryID] {
    let countBefore = order.count
    order.removeAll { $0 == worktreeID }
    if order.count != countBefore {
      didUpdateOrder = true
      if order.isEmpty {
        state.worktreeOrderByRepository.removeValue(forKey: repositoryID)
      } else {
        state.worktreeOrderByRepository[repositoryID] = order
      }
    }
  }
  return WorktreeCleanupStateResult(
    didRemoveWorktree: didRemoveWorktree,
    didUpdatePinned: didUpdatePinned,
    didUpdateOrder: didUpdateOrder
  )
}

nonisolated func archiveScriptCommand(_ script: String) -> String {
  let normalized = script.replacing("\n", with: "\\n")
  return "bash -lc \(shellQuote(normalized))"
}

nonisolated func worktreeCreateCommand(
  baseDirectoryURL: URL,
  name: String,
  copyIgnored: Bool,
  copyUntracked: Bool,
  baseRef: String
) -> String {
  let baseDir = baseDirectoryURL.path(percentEncoded: false)
  var parts = ["wt", "--base-dir", baseDir, "sw"]
  if copyIgnored {
    parts.append("--copy-ignored")
  }
  if copyUntracked {
    parts.append("--copy-untracked")
  }
  if !baseRef.isEmpty {
    parts.append("--from")
    parts.append(baseRef)
  }
  if copyIgnored || copyUntracked {
    parts.append("--verbose")
  }
  parts.append(name)
  return parts.map(shellQuote).joined(separator: " ")
}

nonisolated func shellQuote(_ value: String) -> String {
  "'\(value.replacing("'", with: "'\"'\"'"))'"
}

private func updateWorktreeName(
  _ worktreeID: Worktree.ID,
  name: String,
  state: inout RepositoriesFeature.State
) {
  for index in state.repositories.indices {
    var repository = state.repositories[index]
    guard let worktreeIndex = repository.worktrees.index(id: worktreeID) else {
      continue
    }
    let worktree = repository.worktrees[worktreeIndex]
    guard worktree.name != name else {
      return
    }
    var worktrees = repository.worktrees
    worktrees[id: worktreeID] = Worktree(
      id: worktree.id,
      name: name,
      detail: worktree.detail,
      workingDirectory: worktree.workingDirectory,
      repositoryRootURL: worktree.repositoryRootURL,
      createdAt: worktree.createdAt
    )
    repository = Repository(
      id: repository.id,
      rootURL: repository.rootURL,
      name: repository.name,
      worktrees: worktrees
    )
    state.repositories[index] = repository
    return
  }
}

private func updateWorktreeLineChanges(
  worktreeID: Worktree.ID,
  added: Int,
  removed: Int,
  state: inout RepositoriesFeature.State
) {
  var entry = state.worktreeInfoByID[worktreeID] ?? WorktreeInfoEntry()
  if added == 0 && removed == 0 {
    entry.addedLines = nil
    entry.removedLines = nil
  } else {
    entry.addedLines = added
    entry.removedLines = removed
  }
  if entry.isEmpty {
    state.worktreeInfoByID.removeValue(forKey: worktreeID)
  } else {
    state.worktreeInfoByID[worktreeID] = entry
  }
}

func updateWorktreePullRequest(
  worktreeID: Worktree.ID,
  pullRequest: GithubPullRequest?,
  state: inout RepositoriesFeature.State
) {
  var entry = state.worktreeInfoByID[worktreeID] ?? WorktreeInfoEntry()
  entry.pullRequest = pullRequest
  if entry.isEmpty {
    state.worktreeInfoByID.removeValue(forKey: worktreeID)
  } else {
    state.worktreeInfoByID[worktreeID] = entry
  }
}

func queuePullRequestRefresh(
  repositoryID: Repository.ID,
  repositoryRootURL: URL,
  worktreeIDs: [Worktree.ID],
  refreshesByRepositoryID: inout [Repository.ID: RepositoriesFeature.PendingPullRequestRefresh]
) {
  if var pending = refreshesByRepositoryID[repositoryID] {
    var seenWorktreeIDs = Set(pending.worktreeIDs)
    for worktreeID in worktreeIDs where seenWorktreeIDs.insert(worktreeID).inserted {
      pending.worktreeIDs.append(worktreeID)
    }
    refreshesByRepositoryID[repositoryID] = pending
  } else {
    refreshesByRepositoryID[repositoryID] = RepositoriesFeature.PendingPullRequestRefresh(
      repositoryRootURL: repositoryRootURL,
      worktreeIDs: worktreeIDs
    )
  }
}

func reorderedUnpinnedWorktreeIDs(
  for worktreeID: Worktree.ID,
  in repository: Repository,
  state: RepositoriesFeature.State
) -> [Worktree.ID] {
  var ordered = state.orderedUnpinnedWorktreeIDs(in: repository)
  guard let index = ordered.firstIndex(of: worktreeID) else {
    return ordered
  }
  ordered.remove(at: index)
  ordered.insert(worktreeID, at: 0)
  return ordered
}

func restoreSelection(
  _ id: Worktree.ID?,
  pendingID: Worktree.ID,
  state: inout RepositoriesFeature.State
) {
  guard state.selection == .worktree(pendingID) else { return }
  setSingleWorktreeSelection(
    isSelectionValid(id, state: state) ? id : nil,
    state: &state
  )
}

func isSelectionValid(
  _ id: Worktree.ID?,
  state: RepositoriesFeature.State
) -> Bool {
  state.selectedRow(for: id) != nil
}

private func isSidebarSelectionValid(
  _ selection: SidebarSelection?,
  state: RepositoriesFeature.State
) -> Bool {
  switch selection {
  case .worktree(let id):
    return isSelectionValid(id, state: state)
  case .repository(let id):
    return state.repositories[id: id] != nil
  case .archivedWorktrees, .canvas:
    return true
  case nil:
    return false
  }
}

func setSingleWorktreeSelection(
  _ worktreeID: Worktree.ID?,
  state: inout RepositoriesFeature.State
) {
  state.selection = worktreeID.map(SidebarSelection.worktree)
  if let worktreeID {
    state.sidebarSelectedWorktreeIDs = [worktreeID]
  } else {
    state.sidebarSelectedWorktreeIDs = []
  }
}

func repositoryForWorktreeCreation(
  _ state: RepositoriesFeature.State
) -> Repository? {
  if let selectedRepository = state.selectedRepository,
    selectedRepository.capabilities.supportsWorktrees
  {
    return selectedRepository
  }
  if let selectedWorktreeID = state.selectedWorktreeID {
    if let pending = state.pendingWorktree(for: selectedWorktreeID) {
      if let repository = state.repositories[id: pending.repositoryID],
        repository.capabilities.supportsWorktrees
      {
        return repository
      }
      return nil
    }
    for repository in state.repositories
    where repository.worktrees[id: selectedWorktreeID] != nil {
      if repository.capabilities.supportsWorktrees {
        return repository
      }
      return nil
    }
  }
  if state.repositories.count == 1,
    let repository = state.repositories.first,
    repository.capabilities.supportsWorktrees
  {
    return repository
  }
  return nil
}

private func prunePinnedWorktreeIDs(state: inout RepositoriesFeature.State) -> Bool {
  let availableIDs = Set(state.repositories.flatMap { $0.worktrees.map(\.id) })
  let mainIDs = Set(
    state.repositories.compactMap { repository in
      repository.worktrees.first(where: { state.isMainWorktree($0) })?.id
    }
  )
  let archivedSet = state.archivedWorktreeIDSet
  let pruned = state.pinnedWorktreeIDs.filter {
    availableIDs.contains($0)
      && !mainIDs.contains($0)
      && !archivedSet.contains($0)
  }
  if pruned != state.pinnedWorktreeIDs {
    state.pinnedWorktreeIDs = pruned
    return true
  }
  return false
}

private func pruneRepositoryOrderIDs(
  roots: [URL],
  state: inout RepositoriesFeature.State
) -> Bool {
  let rootIDs = roots.map { $0.standardizedFileURL.path(percentEncoded: false) }
  let availableIDs = Set(rootIDs + state.repositories.map(\.id))
  let pruned = state.repositoryOrderIDs.filter { availableIDs.contains($0) }
  if pruned != state.repositoryOrderIDs {
    state.repositoryOrderIDs = pruned
    return true
  }
  return false
}

private func pruneWorktreeOrderByRepository(
  roots: [URL],
  state: inout RepositoriesFeature.State
) -> Bool {
  let rootIDs = Set(roots.map { $0.standardizedFileURL.path(percentEncoded: false) })
  let repositoriesByID = Dictionary(uniqueKeysWithValues: state.repositories.map { ($0.id, $0) })
  let pinnedSet = Set(state.pinnedWorktreeIDs)
  let archivedSet = state.archivedWorktreeIDSet
  var pruned: [Repository.ID: [Worktree.ID]] = [:]
  for (repoID, order) in state.worktreeOrderByRepository {
    guard let repository = repositoriesByID[repoID] else {
      if rootIDs.contains(repoID), !order.isEmpty {
        pruned[repoID] = order
      }
      continue
    }
    let mainID = repository.worktrees.first(where: { state.isMainWorktree($0) })?.id
    let availableIDs = Set(repository.worktrees.map(\.id))
    var seen: Set<Worktree.ID> = []
    var filtered: [Worktree.ID] = []
    for id in order {
      if availableIDs.contains(id),
        id != mainID,
        !pinnedSet.contains(id),
        !archivedSet.contains(id),
        seen.insert(id).inserted
      {
        filtered.append(id)
      }
    }
    if !filtered.isEmpty {
      pruned[repoID] = filtered
    }
  }
  if pruned != state.worktreeOrderByRepository {
    state.worktreeOrderByRepository = pruned
    return true
  }
  return false
}

private func pruneArchivedWorktrees(
  availableWorktreeIDs: Set<Worktree.ID>,
  state: inout RepositoriesFeature.State
) -> Bool {
  let pruned = state.archivedWorktrees.filter { availableWorktreeIDs.contains($0.id) }
  if pruned != state.archivedWorktrees {
    state.archivedWorktrees = pruned
    return true
  }
  return false
}

func firstAvailableWorktreeID(
  from repositories: [Repository],
  state: RepositoriesFeature.State
) -> Worktree.ID? {
  for repository in repositories {
    if let first = state.orderedWorktrees(in: repository).first {
      return first.id
    }
  }
  return nil
}

func firstAvailableWorktreeID(
  in repositoryID: Repository.ID,
  state: RepositoriesFeature.State
) -> Worktree.ID? {
  guard let repository = state.repositories[id: repositoryID] else {
    return nil
  }
  return state.orderedWorktrees(in: repository).first?.id
}

private func findWorktreeAndRepository(
  worktreeID: Worktree.ID,
  state: RepositoriesFeature.State
) -> (worktree: Worktree, repository: Repository)? {
  for repository in state.repositories {
    if let worktree = repository.worktrees[id: worktreeID] {
      return (worktree, repository)
    }
  }
  return nil
}

func nextWorktreeID(
  afterRemoving worktree: Worktree,
  in repository: Repository,
  state: RepositoriesFeature.State
) -> Worktree.ID? {
  let orderedIDs = state.orderedWorktrees(in: repository).map(\.id)
  guard let index = orderedIDs.firstIndex(of: worktree.id) else { return nil }
  let nextIndex = index + 1
  if nextIndex < orderedIDs.count {
    return orderedIDs[nextIndex]
  }
  if index > 0 {
    return orderedIDs[index - 1]
  }
  return nil
}
