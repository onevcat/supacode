import ComposableArchitecture
import Foundation
import SwiftUI

private enum CancelID {
  static let load = "repositories.load"
}

@Reducer
struct RepositoriesFeature {
  @ObservableState
  struct State: Equatable {
    var repositories: [Repository] = []
    var selectedWorktreeID: Worktree.ID?
    var worktreeInfoByID: [Worktree.ID: WorktreeInfoEntry] = [:]
    var isOpenPanelPresented = false
    var pendingWorktrees: [PendingWorktree] = []
    var pendingSetupScriptWorktreeIDs: Set<Worktree.ID> = []
    var pendingTerminalFocusWorktreeIDs: Set<Worktree.ID> = []
    var deletingWorktreeIDs: Set<Worktree.ID> = []
    var removingRepositoryIDs: Set<Repository.ID> = []
    var pinnedWorktreeIDs: [Worktree.ID] = []
    var shouldSelectFirstAfterReload = false
    @Presents var alert: AlertState<Alert>?
  }

  enum Action: Equatable {
    case task
    case setOpenPanelPresented(Bool)
    case loadPersistedRepositories
    case pinnedWorktreeIDsLoaded([Worktree.ID])
    case refreshWorktrees
    case reloadRepositories(animated: Bool)
    case repositoriesLoaded([Repository], failures: [LoadFailure], roots: [URL], animated: Bool)
    case openRepositories([URL])
    case openRepositoriesFinished(
      [Repository],
      failures: [LoadFailure],
      invalidRoots: [String],
      roots: [URL]
    )
    case selectWorktree(Worktree.ID?)
    case requestRenameBranch(Worktree.ID, String)
    case createRandomWorktree
    case createRandomWorktreeInRepository(Repository.ID)
    case createRandomWorktreeSucceeded(
      Worktree,
      repositoryID: Repository.ID,
      pendingID: Worktree.ID
    )
    case createRandomWorktreeFailed(
      title: String,
      message: String,
      pendingID: Worktree.ID,
      previousSelection: Worktree.ID?
    )
    case consumeSetupScript(Worktree.ID)
    case consumeTerminalFocus(Worktree.ID)
    case requestRemoveWorktree(Worktree.ID, Repository.ID)
    case presentWorktreeRemovalConfirmation(Worktree.ID, Repository.ID)
    case removeWorktreeConfirmed(Worktree.ID, Repository.ID)
    case worktreeRemoved(
      Worktree.ID,
      repositoryID: Repository.ID,
      selectionWasRemoved: Bool,
      nextSelection: Worktree.ID?
    )
    case worktreeRemovalFailed(String, worktreeID: Worktree.ID)
    case requestRemoveRepository(Repository.ID)
    case repositoryRemoved(Repository.ID, selectionWasRemoved: Bool)
    case pinWorktree(Worktree.ID)
    case unpinWorktree(Worktree.ID)
    case presentAlert(title: String, message: String)
    case worktreeInfoEvent(WorktreeInfoWatcherClient.Event)
    case worktreeBranchNameLoaded(worktreeID: Worktree.ID, name: String)
    case worktreeLineChangesLoaded(worktreeID: Worktree.ID, added: Int, removed: Int)
    case worktreePullRequestLoaded(worktreeID: Worktree.ID, pullRequest: GithubPullRequest?)
    case openRepositorySettings(Repository.ID)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
  }

  struct LoadFailure: Equatable {
    let rootID: Repository.ID
    let message: String
  }

  enum Alert: Equatable {
    case confirmRemoveWorktree(Worktree.ID, Repository.ID)
    case confirmRemoveRepository(Repository.ID)
  }

  enum Delegate: Equatable {
    case selectedWorktreeChanged(Worktree?)
    case repositoriesChanged([Repository])
    case openRepositorySettings(Repository.ID)
  }

  @Dependency(\.gitClient) private var gitClient
  @Dependency(\.githubCLI) private var githubCLI
  @Dependency(\.repositoryPersistence) private var repositoryPersistence
  @Dependency(\.repositorySettingsClient) private var repositorySettingsClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          let pinned = await repositoryPersistence.loadPinnedWorktreeIDs()
          await send(.pinnedWorktreeIDsLoaded(pinned))
          await send(.loadPersistedRepositories)
        }

      case .pinnedWorktreeIDsLoaded(let pinnedWorktreeIDs):
        state.pinnedWorktreeIDs = pinnedWorktreeIDs
        return .none

      case .setOpenPanelPresented(let isPresented):
        state.isOpenPanelPresented = isPresented
        return .none

      case .loadPersistedRepositories:
        state.alert = nil
        return .run { send in
          let loadedPaths = await repositoryPersistence.loadRoots()
          let rootPaths = RepositoryPathNormalizer.normalize(loadedPaths)
          let roots = rootPaths.map { URL(fileURLWithPath: $0) }
          let (repositories, failures) = await loadRepositoriesData(roots)
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
        return .send(.reloadRepositories(animated: false))

      case .reloadRepositories(let animated):
        state.alert = nil
        let roots = state.repositories.map(\.rootURL)
        guard !roots.isEmpty else { return .none }
        return loadRepositories(roots, animated: animated)

      case .repositoriesLoaded(let repositories, let failures, let roots, let animated):
        let previousSelection = state.selectedWorktreeID
        let previousSelectedWorktree = state.worktree(for: previousSelection)
        let mergedRepositories = mergeRepositories(
          roots: roots,
          loaded: repositories,
          failures: failures,
          previous: state.repositories
        )
        let didPrunePinned = applyRepositories(
          mergedRepositories,
          state: &state,
          animated: animated
        )
        let errors = failures.map(\.message)
        if !errors.isEmpty {
          state.alert = errorAlert(
            title: errors.count == 1 ? "Failed to load repository" : "Failed to load repositories",
            message: errors.joined(separator: "\n")
          )
        }
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        let selectionChanged = previousSelectedWorktree != selectedWorktree
        var allEffects: [Effect<Action>] = [
          .send(.delegate(.repositoriesChanged(mergedRepositories)))
        ]
        if selectionChanged {
          allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
        }
        if didPrunePinned {
          let pinnedWorktreeIDs = state.pinnedWorktreeIDs
          allEffects.append(
            .run { _ in
              await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
            })
        }
        return .merge(allEffects)

      case .openRepositories(let urls):
        state.alert = nil
        return .run { send in
          let loadedPaths = await repositoryPersistence.loadRoots()
          let existingRootPaths = RepositoryPathNormalizer.normalize(loadedPaths)
          var resolvedRoots: [URL] = []
          var invalidRoots: [String] = []
          for url in urls {
            do {
              let root = try await gitClient.repoRoot(url)
              resolvedRoots.append(root)
            } catch {
              invalidRoots.append(url.path(percentEncoded: false))
            }
          }
          let resolvedRootPaths = RepositoryPathNormalizer.normalize(
            resolvedRoots.map { $0.path(percentEncoded: false) }
          )
          let mergedPaths = RepositoryPathNormalizer.normalize(existingRootPaths + resolvedRootPaths)
          let mergedRoots = mergedPaths.map { URL(fileURLWithPath: $0) }
          await repositoryPersistence.saveRoots(mergedPaths)
          let (repositories, failures) = await loadRepositoriesData(mergedRoots)
          await send(
            .openRepositoriesFinished(
              repositories,
              failures: failures,
              invalidRoots: invalidRoots,
              roots: mergedRoots
            )
          )
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .openRepositoriesFinished(let repositories, let failures, let invalidRoots, let roots):
        let previousSelection = state.selectedWorktreeID
        let previousSelectedWorktree = state.worktree(for: previousSelection)
        let mergedRepositories = mergeRepositories(
          roots: roots,
          loaded: repositories,
          failures: failures,
          previous: state.repositories
        )
        let didPrunePinned = applyRepositories(
          mergedRepositories,
          state: &state,
          animated: false
        )
        if !invalidRoots.isEmpty {
          let message = invalidRoots.map { "\($0) is not a Git repository." }.joined(separator: "\n")
          state.alert = errorAlert(
            title: "Some folders couldn't be opened",
            message: message
          )
        } else {
          let errors = failures.map(\.message)
          if !errors.isEmpty {
            state.alert = errorAlert(
              title: errors.count == 1 ? "Failed to load repository" : "Failed to load repositories",
              message: errors.joined(separator: "\n")
            )
          }
        }
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        let selectionChanged = previousSelectedWorktree != selectedWorktree
        var allEffects: [Effect<Action>] = [
          .send(.delegate(.repositoriesChanged(mergedRepositories)))
        ]
        if selectionChanged {
          allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
        }
        if didPrunePinned {
          let pinnedWorktreeIDs = state.pinnedWorktreeIDs
          allEffects.append(
            .run { _ in
              await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
            })
        }
        return .merge(allEffects)

      case .selectWorktree(let worktreeID):
        state.selectedWorktreeID = worktreeID
        let selectedWorktree = state.worktree(for: worktreeID)
        return .send(.delegate(.selectedWorktreeChanged(selectedWorktree)))

      case .requestRenameBranch(let worktreeID, let branchName):
        guard let worktree = state.worktree(for: worktreeID) else { return .none }
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          state.alert = errorAlert(
            title: "Branch name required",
            message: "Enter a branch name to rename."
          )
          return .none
        }
        guard !trimmed.contains(where: \.isWhitespace) else {
          state.alert = errorAlert(
            title: "Branch name invalid",
            message: "Branch names can't contain spaces."
          )
          return .none
        }
        if trimmed == worktree.name {
          return .none
        }
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

      case .createRandomWorktree:
        guard let repository = repositoryForWorktreeCreation(state) else {
          let message: String
          if state.repositories.isEmpty {
            message = "Open a repository to create a worktree."
          } else if state.selectedWorktreeID == nil && state.repositories.count > 1 {
            message = "Select a worktree to choose which repository to use."
          } else {
            message = "Unable to resolve a repository for the new worktree."
          }
          state.alert = errorAlert(title: "Unable to create worktree", message: message)
          return .none
        }
        return .send(.createRandomWorktreeInRepository(repository.id))

      case .createRandomWorktreeInRepository(let repositoryID):
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }) else {
          state.alert = errorAlert(
            title: "Unable to create worktree",
            message: "Unable to resolve a repository for the new worktree."
          )
          return .none
        }
        if state.removingRepositoryIDs.contains(repository.id) {
          state.alert = errorAlert(
            title: "Unable to create worktree",
            message: "This repository is being removed."
          )
          return .none
        }
        let previousSelection = state.selectedWorktreeID
        let pendingID = "pending:\(UUID().uuidString)"
        let repositorySettings = repositorySettingsClient.load(repository.rootURL)
        state.pendingWorktrees.append(
          PendingWorktree(
            id: pendingID,
            repositoryID: repository.id,
            name: "Creating worktree...",
            detail: ""
          )
        )
        state.selectedWorktreeID = pendingID
        let existingNames = Set(repository.worktrees.map { $0.name.lowercased() })
        return .run { send in
          do {
            let branchNames = try await gitClient.localBranchNames(repository.rootURL)
            let existing = existingNames.union(branchNames)
            let name = await MainActor.run {
              WorktreeNameGenerator.nextName(excluding: existing)
            }
            guard let name else {
              let message =
                "All default adjective-animal names are already in use. "
                + "Delete a worktree or rename a branch, then try again."
              await send(
                .createRandomWorktreeFailed(
                  title: "No available worktree names",
                  message: message,
                  pendingID: pendingID,
                  previousSelection: previousSelection
                )
              )
              return
            }
            let newWorktree = try await gitClient.createWorktree(
              name,
              repository.rootURL,
              repositorySettings.copyIgnoredOnWorktreeCreate,
              repositorySettings.copyUntrackedOnWorktreeCreate
            )
            await send(
              .createRandomWorktreeSucceeded(
                newWorktree,
                repositoryID: repository.id,
                pendingID: pendingID
              )
            )
          } catch {
            await send(
              .createRandomWorktreeFailed(
                title: "Unable to create worktree",
                message: error.localizedDescription,
                pendingID: pendingID,
                previousSelection: previousSelection
              )
            )
          }
        }

      case .createRandomWorktreeSucceeded(
        let worktree,
        let repositoryID,
        let pendingID
      ):
        state.pendingSetupScriptWorktreeIDs.insert(worktree.id)
        state.pendingTerminalFocusWorktreeIDs.insert(worktree.id)
        removePendingWorktree(pendingID, state: &state)
        if state.selectedWorktreeID == pendingID {
          state.selectedWorktreeID = worktree.id
        }
        insertWorktree(worktree, repositoryID: repositoryID, state: &state)
        return .merge(
          .send(.reloadRepositories(animated: false)),
          .send(.delegate(.repositoriesChanged(state.repositories))),
          .send(.delegate(.selectedWorktreeChanged(state.worktree(for: state.selectedWorktreeID))))
        )

      case .createRandomWorktreeFailed(
        let title,
        let message,
        let pendingID,
        let previousSelection
      ):
        removePendingWorktree(pendingID, state: &state)
        restoreSelection(previousSelection, pendingID: pendingID, state: &state)
        state.alert = errorAlert(title: title, message: message)
        return .none

      case .consumeSetupScript(let id):
        state.pendingSetupScriptWorktreeIDs.remove(id)
        return .none

      case .consumeTerminalFocus(let id):
        state.pendingTerminalFocusWorktreeIDs.remove(id)
        return .none

      case .requestRemoveWorktree(let worktreeID, let repositoryID):
        if state.removingRepositoryIDs.contains(repositoryID) {
          return .none
        }
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }),
          let worktree = repository.worktrees.first(where: { $0.id == worktreeID })
        else {
          return .none
        }
        if state.isMainWorktree(worktree) {
          return .none
        }
        if state.deletingWorktreeIDs.contains(worktree.id) {
          return .none
        }
        return .send(.presentWorktreeRemovalConfirmation(worktree.id, repository.id))

      case .presentWorktreeRemovalConfirmation(let worktreeID, let repositoryID):
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }),
          let worktree = repository.worktrees.first(where: { $0.id == worktreeID })
        else {
          return .none
        }
        state.alert = AlertState {
          TextState("🚨 Remove worktree?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmRemoveWorktree(worktree.id, repository.id)) {
            TextState("Remove")
          }
          ButtonState(role: .cancel) {
            TextState("Cancel")
          }
        } message: {
          TextState(
            "Remove \(worktree.name)? "
              + "This deletes the worktree directory and its branch."
          )
        }
        return .none

      case .alert(.presented(.confirmRemoveWorktree(let worktreeID, let repositoryID))):
        return .send(.removeWorktreeConfirmed(worktreeID, repositoryID))

      case .removeWorktreeConfirmed(let worktreeID, let repositoryID):
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }),
          let worktree = repository.worktrees.first(where: { $0.id == worktreeID })
        else {
          return .none
        }
        if state.deletingWorktreeIDs.contains(worktree.id) {
          return .none
        }
        state.alert = nil
        state.deletingWorktreeIDs.insert(worktree.id)
        let selectionWasRemoved = state.selectedWorktreeID == worktree.id
        let nextSelection =
          selectionWasRemoved
          ? nextWorktreeID(afterRemoving: worktree, in: repository, state: state)
          : nil
        return .run { send in
          do {
            _ = try await gitClient.removeWorktree(worktree)
            await send(
              .worktreeRemoved(
                worktree.id,
                repositoryID: repository.id,
                selectionWasRemoved: selectionWasRemoved,
                nextSelection: nextSelection
              )
            )
          } catch {
            await send(.worktreeRemovalFailed(error.localizedDescription, worktreeID: worktree.id))
          }
        }

      case .worktreeRemoved(
        let worktreeID,
        let repositoryID,
        _,
        let nextSelection
      ):
        let previousSelection = state.selectedWorktreeID
        let previousSelectedWorktree = state.worktree(for: previousSelection)
        let wasPinned = state.pinnedWorktreeIDs.contains(worktreeID)
        state.deletingWorktreeIDs.remove(worktreeID)
        state.pendingWorktrees.removeAll { $0.id == worktreeID }
        state.pendingSetupScriptWorktreeIDs.remove(worktreeID)
        state.pendingTerminalFocusWorktreeIDs.remove(worktreeID)
        state.worktreeInfoByID.removeValue(forKey: worktreeID)
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        _ = removeWorktree(worktreeID, repositoryID: repositoryID, state: &state)
        let selectionNeedsUpdate = state.selectedWorktreeID == worktreeID
        if selectionNeedsUpdate {
          state.selectedWorktreeID =
            nextSelection ?? firstAvailableWorktreeID(in: repositoryID, state: state)
        }
        let roots = state.repositories.map(\.rootURL)
        let repositories = state.repositories
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        let selectionChanged = previousSelectedWorktree != selectedWorktree
        var immediateEffects: [Effect<Action>] = [
          .send(.delegate(.repositoriesChanged(repositories)))
        ]
        if selectionChanged {
          immediateEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
        }
        var followupEffects: [Effect<Action>] = [
          roots.isEmpty ? .none : .send(.reloadRepositories(animated: true))
        ]
        if wasPinned {
          let pinnedWorktreeIDs = state.pinnedWorktreeIDs
          followupEffects.append(
            .run { _ in
              await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
            }
          )
        }
        return .concatenate(
          .merge(immediateEffects),
          .merge(followupEffects)
        )

      case .worktreeRemovalFailed(let message, let worktreeID):
        state.deletingWorktreeIDs.remove(worktreeID)
        state.alert = errorAlert(title: "Unable to remove worktree", message: message)
        return .none

      case .requestRemoveRepository(let repositoryID):
        state.alert = confirmationAlertForRepositoryRemoval(repositoryID: repositoryID, state: state)
        return .none

      case .alert(.presented(.confirmRemoveRepository(let repositoryID))):
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }) else {
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
        return .send(.repositoryRemoved(repository.id, selectionWasRemoved: selectionWasRemoved))

      case .repositoryRemoved(let repositoryID, let selectionWasRemoved):
        state.removingRepositoryIDs.remove(repositoryID)
        if selectionWasRemoved {
          state.selectedWorktreeID = nil
          state.shouldSelectFirstAfterReload = true
        }
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        return .merge(
          .send(.delegate(.selectedWorktreeChanged(selectedWorktree))),
          .run { send in
            let loadedPaths = await repositoryPersistence.loadRoots()
            var seen: Set<String> = []
            let rootPaths = loadedPaths.filter { seen.insert($0).inserted }
            let remaining = rootPaths.filter { $0 != repositoryID }
            await repositoryPersistence.saveRoots(remaining)
            let roots = remaining.map { URL(fileURLWithPath: $0) }
            let (repositories, failures) = await loadRepositoriesData(roots)
            await send(
              .repositoriesLoaded(
                repositories,
                failures: failures,
                roots: roots,
                animated: true
              )
            )
          }
          .cancellable(id: CancelID.load, cancelInFlight: true)
        )

      case .pinWorktree(let worktreeID):
        if let worktree = state.worktree(for: worktreeID), state.isMainWorktree(worktree) {
          let wasPinned = state.pinnedWorktreeIDs.contains(worktreeID)
          state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
          if wasPinned {
            let pinnedWorktreeIDs = state.pinnedWorktreeIDs
            return .run { _ in
              await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
            }
          }
          return .none
        }
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        state.pinnedWorktreeIDs.insert(worktreeID, at: 0)
        let pinnedWorktreeIDs = state.pinnedWorktreeIDs
        return .run { _ in
          await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
        }

      case .unpinWorktree(let worktreeID):
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        let pinnedWorktreeIDs = state.pinnedWorktreeIDs
        return .run { _ in
          await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
        }

      case .presentAlert(let title, let message):
        state.alert = errorAlert(title: title, message: message)
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
          let worktrees = worktreeIDs.compactMap { state.worktree(for: $0) }
          var seen = Set<String>()
          let branches = worktrees
            .map(\.name)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
          guard !branches.isEmpty else {
            return .none
          }
          let gitClient = gitClient
          let githubCLI = githubCLI
          return .run { send in
            guard await githubCLI.isAvailable() else {
              return
            }
            guard let remoteInfo = await gitClient.remoteInfo(repositoryRootURL) else {
              return
            }
            let result = await Result {
              try await githubCLI.batchPullRequests(
                remoteInfo.host,
                remoteInfo.owner,
                remoteInfo.repo,
                branches
              )
            }
            switch result {
            case .success(let prsByBranch):
              for worktree in worktrees {
                let pullRequest = prsByBranch[worktree.name]
                await send(
                  .worktreePullRequestLoaded(worktreeID: worktree.id, pullRequest: pullRequest)
                )
              }
            case .failure:
              return
            }
          }
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

      case .worktreePullRequestLoaded(let worktreeID, let pullRequest):
        updateWorktreePullRequest(
          worktreeID: worktreeID,
          pullRequest: pullRequest,
          state: &state
        )
        return .none

      case .openRepositorySettings(let repositoryID):
        return .send(.delegate(.openRepositorySettings(repositoryID)))

      case .alert(.dismiss):
        state.alert = nil
        return .none

      case .alert:
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func loadRepositories(_ roots: [URL], animated: Bool = false) -> Effect<Action> {
    .run { [animated, roots] send in
      let (repositories, failures) = await loadRepositoriesData(roots)
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

  private func loadRepositoriesData(_ roots: [URL]) async -> ([Repository], [LoadFailure]) {
    var loaded: [Repository] = []
    var failures: [LoadFailure] = []
    for root in roots {
      let normalizedRoot = root.standardizedFileURL
      let rootID = normalizedRoot.path(percentEncoded: false)
      do {
        let worktrees = try await gitClient.worktrees(root)
        let name = repositoryName(from: normalizedRoot)
        let repository = Repository(
          id: rootID,
          rootURL: normalizedRoot,
          name: name,
          worktrees: worktrees
        )
        loaded.append(repository)
      } catch {
        failures.append(LoadFailure(rootID: rootID, message: error.localizedDescription))
      }
    }
    return (loaded, failures)
  }

  private func applyRepositories(
    _ repositories: [Repository],
    state: inout State,
    animated: Bool
  ) -> Bool {
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
    let filteredWorktreeInfo = state.worktreeInfoByID.filter {
      availableWorktreeIDs.contains($0.key)
    }
    if animated {
      withAnimation {
        state.repositories = repositories
        state.pendingWorktrees = filteredPendingWorktrees
        state.deletingWorktreeIDs = filteredDeletingIDs
        state.pendingSetupScriptWorktreeIDs = filteredSetupScriptIDs
        state.pendingTerminalFocusWorktreeIDs = filteredFocusIDs
        state.worktreeInfoByID = filteredWorktreeInfo
      }
    } else {
      state.repositories = repositories
      state.pendingWorktrees = filteredPendingWorktrees
      state.deletingWorktreeIDs = filteredDeletingIDs
      state.pendingSetupScriptWorktreeIDs = filteredSetupScriptIDs
      state.pendingTerminalFocusWorktreeIDs = filteredFocusIDs
      state.worktreeInfoByID = filteredWorktreeInfo
    }
    let didPrunePinned = prunePinnedWorktreeIDs(state: &state)
    if !isSelectionValid(state.selectedWorktreeID, state: state) {
      state.selectedWorktreeID = nil
    }
    if state.selectedWorktreeID == nil, state.shouldSelectFirstAfterReload {
      state.selectedWorktreeID = firstAvailableWorktreeID(from: repositories, state: state)
      state.shouldSelectFirstAfterReload = false
    }
    return didPrunePinned
  }

  private func mergeRepositories(
    roots: [URL],
    loaded: [Repository],
    failures: [LoadFailure],
    previous: [Repository]
  ) -> [Repository] {
    guard !roots.isEmpty else {
      return loaded
    }
    let loadedByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
    let failedIDs = Set(failures.map(\.rootID))
    var merged: [Repository] = []
    merged.reserveCapacity(roots.count)
    for root in roots {
      let rootID = root.standardizedFileURL.path(percentEncoded: false)
      if let repository = loadedByID[rootID] {
        merged.append(repository)
      } else if failedIDs.contains(rootID), let repository = previousByID[rootID] {
        merged.append(repository)
      }
    }
    if merged.isEmpty {
      return loaded
    }
    let mergedIDs = Set(merged.map(\.id))
    for repository in loaded where !mergedIDs.contains(repository.id) {
      merged.append(repository)
    }
    return merged
  }

  private func errorAlert(title: String, message: String) -> AlertState<Alert> {
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

  private func confirmationAlertForRepositoryRemoval(
    repositoryID: Repository.ID,
    state: State
  ) -> AlertState<Alert>? {
    guard let repository = state.repositories.first(where: { $0.id == repositoryID }) else {
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
        "This removes the repository from Supacode. "
          + "Worktrees and the main repository folder stay on disk."
      )
    }
  }
}

extension RepositoriesFeature.State {
  func worktreeInfo(for worktreeID: Worktree.ID) -> WorktreeInfoEntry? {
    worktreeInfoByID[worktreeID]
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
      if let worktree = repository.worktrees.first(where: { $0.id == id }) {
        return worktree
      }
    }
    return nil
  }

  func pendingWorktree(for id: Worktree.ID?) -> PendingWorktree? {
    guard let id else { return nil }
    return pendingWorktrees.first(where: { $0.id == id })
  }

  func shouldFocusTerminal(for worktreeID: Worktree.ID) -> Bool {
    pendingTerminalFocusWorktreeIDs.contains(worktreeID)
  }

  func selectedRow(for id: Worktree.ID?) -> WorktreeRowModel? {
    guard let id else { return nil }
    if let pending = pendingWorktree(for: id) {
      let isDeleting = removingRepositoryIDs.contains(pending.repositoryID)
      return WorktreeRowModel(
        id: pending.id,
        repositoryID: pending.repositoryID,
        name: pending.name,
        detail: pending.detail,
        info: worktreeInfo(for: pending.id),
        isPinned: false,
        isMainWorktree: false,
        isPending: true,
        isDeleting: isDeleting,
        isRemovable: false
      )
    }
    for repository in repositories {
      if let worktree = repository.worktrees.first(where: { $0.id == id }) {
        let isDeleting =
          removingRepositoryIDs.contains(repository.id)
          || deletingWorktreeIDs.contains(worktree.id)
        return WorktreeRowModel(
          id: worktree.id,
          repositoryID: repository.id,
          name: worktree.name,
          detail: worktree.detail,
          info: worktreeInfo(for: worktree.id),
          isPinned: pinnedWorktreeIDs.contains(worktree.id),
          isMainWorktree: isMainWorktree(worktree),
          isPending: false,
          isDeleting: isDeleting,
          isRemovable: !isDeleting
        )
      }
    }
    return nil
  }

  func repositoryName(for id: Repository.ID) -> String? {
    repositories.first(where: { $0.id == id })?.name
  }

  func repositoryID(for worktreeID: Worktree.ID?) -> Repository.ID? {
    selectedRow(for: worktreeID)?.repositoryID
  }

  func isMainWorktree(_ worktree: Worktree) -> Bool {
    worktree.workingDirectory.standardizedFileURL == worktree.repositoryRootURL.standardizedFileURL
  }

  func orderedWorktrees(in repository: Repository) -> [Worktree] {
    let worktreeByID = Dictionary(uniqueKeysWithValues: repository.worktrees.map { ($0.id, $0) })
    var ordered: [Worktree] = []
    var seen: Set<Worktree.ID> = []
    if let mainWorktree = repository.worktrees.first(where: { isMainWorktree($0) }) {
      ordered.append(mainWorktree)
      seen.insert(mainWorktree.id)
    }
    for id in pinnedWorktreeIDs {
      if let worktree = worktreeByID[id], !seen.contains(id) {
        ordered.append(worktree)
        seen.insert(id)
      }
    }
    for worktree in repository.worktrees where !seen.contains(worktree.id) {
      ordered.append(worktree)
    }
    return ordered
  }

  func isWorktreePinned(_ worktree: Worktree) -> Bool {
    pinnedWorktreeIDs.contains(worktree.id)
  }

  func isRemovingRepository(_ repository: Repository) -> Bool {
    removingRepositoryIDs.contains(repository.id)
  }

  func worktreeRows(in repository: Repository) -> [WorktreeRowModel] {
    let ordered = orderedWorktrees(in: repository)
    let pinnedIDs = Set(pinnedWorktreeIDs)
    let isRemovingRepository = removingRepositoryIDs.contains(repository.id)
    let mainWorktreeID = repository.worktrees.first(where: { isMainWorktree($0) })?.id
    let mainWorktree = mainWorktreeID.flatMap { id in ordered.first(where: { $0.id == id }) }
    let pinnedWorktrees = ordered.filter { pinnedIDs.contains($0.id) }
    let unpinnedWorktrees = ordered.filter { !pinnedIDs.contains($0.id) }
    let pendingEntries = pendingWorktrees.filter { $0.repositoryID == repository.id }
    var rows: [WorktreeRowModel] = []
    if let mainWorktree {
      let isDeleting = isRemovingRepository || deletingWorktreeIDs.contains(mainWorktree.id)
      rows.append(
        WorktreeRowModel(
          id: mainWorktree.id,
          repositoryID: repository.id,
          name: mainWorktree.name,
          detail: mainWorktree.detail,
          info: worktreeInfo(for: mainWorktree.id),
          isPinned: false,
          isMainWorktree: true,
          isPending: false,
          isDeleting: isDeleting,
          isRemovable: !isDeleting
        )
      )
    }
    for worktree in pinnedWorktrees {
      if worktree.id == mainWorktreeID {
        continue
      }
      let isDeleting = isRemovingRepository || deletingWorktreeIDs.contains(worktree.id)
      rows.append(
        WorktreeRowModel(
          id: worktree.id,
          repositoryID: repository.id,
          name: worktree.name,
          detail: worktree.detail,
          info: worktreeInfo(for: worktree.id),
          isPinned: true,
          isMainWorktree: false,
          isPending: false,
          isDeleting: isDeleting,
          isRemovable: !isDeleting
        )
      )
    }
    for pending in pendingEntries {
      rows.append(
        WorktreeRowModel(
          id: pending.id,
          repositoryID: pending.repositoryID,
          name: pending.name,
          detail: pending.detail,
          info: worktreeInfo(for: pending.id),
          isPinned: false,
          isMainWorktree: false,
          isPending: true,
          isDeleting: isRemovingRepository,
          isRemovable: false
        )
      )
    }
    for worktree in unpinnedWorktrees {
      if worktree.id == mainWorktreeID {
        continue
      }
      let isDeleting = isRemovingRepository || deletingWorktreeIDs.contains(worktree.id)
      rows.append(
        WorktreeRowModel(
          id: worktree.id,
          repositoryID: repository.id,
          name: worktree.name,
          detail: worktree.detail,
          info: worktreeInfo(for: worktree.id),
          isPinned: false,
          isMainWorktree: false,
          isPending: false,
          isDeleting: isDeleting,
          isRemovable: !isDeleting
        )
      )
    }
    return rows
  }

  func orderedWorktreeRows() -> [WorktreeRowModel] {
    repositories.flatMap { worktreeRows(in: $0) }
  }
}

private func removePendingWorktree(_ id: String, state: inout RepositoriesFeature.State) {
  state.pendingWorktrees.removeAll { $0.id == id }
}

private func insertWorktree(
  _ worktree: Worktree,
  repositoryID: Repository.ID,
  state: inout RepositoriesFeature.State
) {
  guard let index = state.repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
  let repository = state.repositories[index]
  if repository.worktrees.contains(where: { $0.id == worktree.id }) {
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
private func removeWorktree(
  _ worktreeID: Worktree.ID,
  repositoryID: Repository.ID,
  state: inout RepositoriesFeature.State
) -> Bool {
  guard let index = state.repositories.firstIndex(where: { $0.id == repositoryID }) else { return false }
  let repository = state.repositories[index]
  let filteredWorktrees = repository.worktrees.filter { $0.id != worktreeID }
  guard filteredWorktrees.count != repository.worktrees.count else { return false }
  state.repositories[index] = Repository(
    id: repository.id,
    rootURL: repository.rootURL,
    name: repository.name,
    worktrees: filteredWorktrees
  )
  return true
}

private func updateWorktreeName(
  _ worktreeID: Worktree.ID,
  name: String,
  state: inout RepositoriesFeature.State
) {
  for index in state.repositories.indices {
    var repository = state.repositories[index]
    guard let worktreeIndex = repository.worktrees.firstIndex(where: { $0.id == worktreeID }) else {
      continue
    }
    let worktree = repository.worktrees[worktreeIndex]
    guard worktree.name != name else {
      return
    }
    var worktrees = repository.worktrees
    worktrees[worktreeIndex] = Worktree(
      id: worktree.id,
      name: name,
      detail: worktree.detail,
      workingDirectory: worktree.workingDirectory,
      repositoryRootURL: worktree.repositoryRootURL
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

private func updateWorktreePullRequest(
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

private func restoreSelection(
  _ id: Worktree.ID?,
  pendingID: Worktree.ID,
  state: inout RepositoriesFeature.State
) {
  guard state.selectedWorktreeID == pendingID else { return }
  if isSelectionValid(id, state: state) {
    state.selectedWorktreeID = id
  } else {
    state.selectedWorktreeID = nil
  }
}

private func isSelectionValid(
  _ id: Worktree.ID?,
  state: RepositoriesFeature.State
) -> Bool {
  state.selectedRow(for: id) != nil
}

private func repositoryForWorktreeCreation(
  _ state: RepositoriesFeature.State
) -> Repository? {
  if let selectedWorktreeID = state.selectedWorktreeID {
    if let pending = state.pendingWorktree(for: selectedWorktreeID) {
      return state.repositories.first(where: { $0.id == pending.repositoryID })
    }
    for repository in state.repositories
    where repository.worktrees.contains(where: { $0.id == selectedWorktreeID }) {
      return repository
    }
  }
  if state.repositories.count == 1 {
    return state.repositories.first
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
  let pruned = state.pinnedWorktreeIDs.filter { availableIDs.contains($0) && !mainIDs.contains($0) }
  if pruned != state.pinnedWorktreeIDs {
    state.pinnedWorktreeIDs = pruned
    return true
  }
  return false
}

private func firstAvailableWorktreeID(
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

private func firstAvailableWorktreeID(
  in repositoryID: Repository.ID,
  state: RepositoriesFeature.State
) -> Worktree.ID? {
  guard let repository = state.repositories.first(where: { $0.id == repositoryID }) else {
    return nil
  }
  return state.orderedWorktrees(in: repository).first?.id
}

private func nextWorktreeID(
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

private func repositoryName(from root: URL) -> String {
  let name = root.lastPathComponent
  if name.isEmpty {
    return root.path(percentEncoded: false)
  }
  return name
}
