import ComposableArchitecture
import Foundation
import SwiftUI

private enum CancelID {
  static let load = "repositories.load"
  static let debounce = "repositories.debounce"
  static let periodic = "repositories.periodic"

  static func watcher(_ id: Repository.ID) -> String {
    "repositories.watcher.\(id)"
  }
}

@Reducer
struct RepositoriesFeature {
  @ObservableState
  struct State: Equatable {
    var repositories: [Repository] = []
    var selectedWorktreeID: Worktree.ID?
    var isOpenPanelPresented = false
    var pendingWorktrees: [PendingWorktree] = []
    var pendingSetupScriptWorktreeIDs: Set<Worktree.ID> = []
    var deletingWorktreeIDs: Set<Worktree.ID> = []
    var removingRepositoryIDs: Set<Repository.ID> = []
    var pinnedWorktreeIDs: [Worktree.ID] = []
    var watchingRepositoryIDs: Set<Repository.ID> = []
    var shouldSelectFirstAfterReload = false
    @Presents var alert: AlertState<Alert>?
  }

  enum Action: Equatable {
    case task
    case setOpenPanelPresented(Bool)
    case loadPersistedRepositories
    case refreshWorktrees
    case reloadRepositories(animated: Bool)
    case repositoriesLoaded([Repository], errors: [String], animated: Bool)
    case startPeriodicRefresh
    case stopPeriodicRefresh
    case periodicRefreshTick
    case openRepositories([URL])
    case openRepositoriesFinished([Repository], errors: [String], failures: [String])
    case selectWorktree(Worktree.ID?)
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
    case repositoryRemovalFailed(String, repositoryID: Repository.ID)
    case pinWorktree(Worktree.ID)
    case unpinWorktree(Worktree.ID)
    case repositoryChangeDetected(Repository.ID)
    case scheduleReload(animated: Bool)
    case presentAlert(title: String, message: String)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
  }

  enum Alert: Equatable {
    case confirmRemoveWorktree(Worktree.ID, Repository.ID)
    case confirmRemoveRepository(Repository.ID)
  }

  enum Delegate: Equatable {
    case selectedWorktreeChanged(Worktree?)
    case repositoriesChanged([Repository])
    case repositoryChanged(Repository.ID)
  }

  @Dependency(\.gitClient) private var gitClient
  @Dependency(\.repositoryPersistence) private var repositoryPersistence
  @Dependency(\.repositoryWatcher) private var repositoryWatcher
  @Dependency(\.continuousClock) private var clock

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .task:
        state.pinnedWorktreeIDs = repositoryPersistence.loadPinnedWorktreeIDs()
        return .send(.loadPersistedRepositories)

      case .setOpenPanelPresented(let isPresented):
        state.isOpenPanelPresented = isPresented
        return .none

      case .loadPersistedRepositories:
        state.alert = nil
        let rootPaths = uniqueRootPaths(repositoryPersistence.loadRoots())
        let roots = rootPaths.map { URL(fileURLWithPath: $0) }
        return loadRepositories(roots, animated: false)

      case .refreshWorktrees:
        return .send(.reloadRepositories(animated: false))

      case .startPeriodicRefresh:
        return .merge(
          .cancel(id: CancelID.periodic),
          periodicRefreshEffect()
        )

      case .stopPeriodicRefresh:
        return .cancel(id: CancelID.periodic)

      case .periodicRefreshTick:
        return .send(.reloadRepositories(animated: false))

      case .reloadRepositories(let animated):
        state.alert = nil
        let roots = state.repositories.map(\.rootURL)
        guard !roots.isEmpty else { return .none }
        return loadRepositories(roots, animated: animated)

      case .repositoriesLoaded(let repositories, let errors, let animated):
        let previousWatching = state.watchingRepositoryIDs
        let previousSelection = state.selectedWorktreeID
        applyRepositories(repositories, state: &state, animated: animated)
        if !errors.isEmpty {
          state.alert = errorAlert(
            title: errors.count == 1 ? "Failed to load repository" : "Failed to load repositories",
            message: errors.joined(separator: "\n")
          )
        }
        let selectionChanged = previousSelection != state.selectedWorktreeID
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        let effects = watcherEffects(
          previousWatching: previousWatching,
          repositories: repositories,
          state: &state
        )
        var allEffects: [Effect<Action>] = [effects, .send(.delegate(.repositoriesChanged(repositories)))]
        if selectionChanged {
          allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
        }
        return .merge(allEffects)

      case .openRepositories(let urls):
        state.alert = nil
        return .run { send in
          let existingRootPaths = await MainActor.run {
            uniqueRootPaths(repositoryPersistence.loadRoots())
          }
          var resolvedRoots: [URL] = []
          var failures: [String] = []
          for url in urls {
            do {
              let root = try await gitClient.repoRoot(url)
              resolvedRoots.append(root)
            } catch {
              failures.append(url.path(percentEncoded: false))
            }
          }
          var mergedPaths = existingRootPaths
          for root in resolvedRoots {
            let normalized = root.standardizedFileURL.path(percentEncoded: false)
            if !mergedPaths.contains(normalized) {
              mergedPaths.append(normalized)
            }
          }
          let mergedPathsSnapshot = mergedPaths
          let mergedRoots = await MainActor.run {
            uniqueRootPaths(mergedPathsSnapshot)
          }.map { URL(fileURLWithPath: $0) }
          let (repositories, errors) = await loadRepositoriesData(mergedRoots)
          await send(
            .openRepositoriesFinished(repositories, errors: errors, failures: failures)
          )
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .openRepositoriesFinished(let repositories, let errors, let failures):
        let previousWatching = state.watchingRepositoryIDs
        let previousSelection = state.selectedWorktreeID
        applyRepositories(repositories, state: &state, animated: false)
        if !failures.isEmpty {
          let message = failures.map { "\($0) is not a Git repository." }.joined(separator: "\n")
          state.alert = errorAlert(
            title: "Some folders couldn't be opened",
            message: message
          )
        } else if !errors.isEmpty {
          state.alert = errorAlert(
            title: errors.count == 1 ? "Failed to load repository" : "Failed to load repositories",
            message: errors.joined(separator: "\n")
          )
        }
        let selectionChanged = previousSelection != state.selectedWorktreeID
        let selectedWorktree = state.worktree(for: state.selectedWorktreeID)
        let effects = watcherEffects(
          previousWatching: previousWatching,
          repositories: repositories,
          state: &state
        )
        var allEffects: [Effect<Action>] = [effects, .send(.delegate(.repositoriesChanged(repositories)))]
        if selectionChanged {
          allEffects.append(.send(.delegate(.selectedWorktreeChanged(selectedWorktree))))
        }
        return .merge(allEffects)

      case .selectWorktree(let worktreeID):
        state.selectedWorktreeID = worktreeID
        let selectedWorktree = state.worktree(for: worktreeID)
        return .send(.delegate(.selectedWorktreeChanged(selectedWorktree)))

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
                "All default animal names are already in use. "
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
            let newWorktree = try await gitClient.createWorktree(name, repository.rootURL)
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
        removePendingWorktree(pendingID, state: &state)
        if state.selectedWorktreeID == pendingID {
          state.selectedWorktreeID = worktree.id
        }
        insertWorktree(worktree, repositoryID: repositoryID, state: &state)
        return .merge(
          .send(.reloadRepositories(animated: false)),
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
        return .run { send in
          do {
            let dirty = try await gitClient.isWorktreeDirty(worktree.workingDirectory)
            if dirty {
              await send(.presentWorktreeRemovalConfirmation(worktree.id, repository.id))
            } else {
              await send(.removeWorktreeConfirmed(worktree.id, repository.id))
            }
          } catch {
            await send(.worktreeRemovalFailed(error.localizedDescription, worktreeID: worktree.id))
          }
        }

      case .presentWorktreeRemovalConfirmation(let worktreeID, let repositoryID):
        guard let repository = state.repositories.first(where: { $0.id == repositoryID }),
          let worktree = repository.worktrees.first(where: { $0.id == worktreeID })
        else {
          return .none
        }
        state.alert = AlertState {
          TextState("Worktree has uncommitted changes")
        } actions: {
          ButtonState(role: .destructive, action: .confirmRemoveWorktree(worktree.id, repository.id)) {
            TextState("Remove anyway")
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
        let nextSelection = selectionWasRemoved
          ? nextWorktreeID(afterRemoving: worktree, in: repository, state: state)
          : nil
        return .run { send in
          do {
            _ = try await gitClient.removeWorktree(worktree, true)
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
        let selectionWasRemoved,
        let nextSelection
      ):
        state.deletingWorktreeIDs.remove(worktreeID)
        state.pendingSetupScriptWorktreeIDs.remove(worktreeID)
        let roots = state.repositories.map(\.rootURL)
        if selectionWasRemoved {
          state.selectedWorktreeID =
            nextSelection ?? firstAvailableWorktreeID(in: repositoryID, state: state)
        }
        return .merge(
          roots.isEmpty ? .none : .send(.reloadRepositories(animated: true)),
          .send(.delegate(.selectedWorktreeChanged(state.worktree(for: state.selectedWorktreeID))))
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
        let selectionWasRemoved = state.selectedWorktreeID.map { id in
          repository.worktrees.contains(where: { $0.id == id })
        } ?? false
        return .run { send in
          var failures: [String] = []
          for worktree in repository.worktrees {
            do {
              _ = try await gitClient.removeWorktree(worktree, true)
            } catch {
              failures.append(error.localizedDescription)
            }
          }
          if failures.isEmpty {
            await send(.repositoryRemoved(repository.id, selectionWasRemoved: selectionWasRemoved))
          } else {
            await send(.repositoryRemovalFailed(failures.joined(separator: "\n"), repositoryID: repository.id))
          }
        }

      case .repositoryRemoved(let repositoryID, let selectionWasRemoved):
        state.removingRepositoryIDs.remove(repositoryID)
        let rootPaths = uniqueRootPaths(repositoryPersistence.loadRoots())
        let remaining = rootPaths.filter { $0 != repositoryID }
        repositoryPersistence.saveRoots(remaining)
        let roots = uniqueRootPaths(repositoryPersistence.loadRoots()).map { URL(fileURLWithPath: $0) }
        if selectionWasRemoved {
          state.selectedWorktreeID = nil
          state.shouldSelectFirstAfterReload = true
        }
        return .merge(
          roots.isEmpty ? .none : .send(.reloadRepositories(animated: true)),
          .send(.delegate(.selectedWorktreeChanged(state.worktree(for: state.selectedWorktreeID))))
        )

      case .repositoryRemovalFailed(let message, let repositoryID):
        state.removingRepositoryIDs.remove(repositoryID)
        state.alert = errorAlert(title: "Unable to remove repository", message: message)
        return .none

      case .pinWorktree(let worktreeID):
        if let worktree = state.worktree(for: worktreeID), state.isMainWorktree(worktree) {
          let wasPinned = state.pinnedWorktreeIDs.contains(worktreeID)
          state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
          if wasPinned {
            repositoryPersistence.savePinnedWorktreeIDs(state.pinnedWorktreeIDs)
          }
          return .none
        }
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        state.pinnedWorktreeIDs.insert(worktreeID, at: 0)
        repositoryPersistence.savePinnedWorktreeIDs(state.pinnedWorktreeIDs)
        return .none

      case .unpinWorktree(let worktreeID):
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        repositoryPersistence.savePinnedWorktreeIDs(state.pinnedWorktreeIDs)
        return .none

      case .repositoryChangeDetected(let repositoryID):
        return .merge(
          .send(.scheduleReload(animated: true)),
          .send(.delegate(.repositoryChanged(repositoryID)))
        )

      case .scheduleReload(let animated):
        let roots = state.repositories.map(\.rootURL)
        guard !roots.isEmpty else { return .none }
        return .run { send in
          try await clock.sleep(for: .milliseconds(350))
          await send(.reloadRepositories(animated: animated))
        }
        .cancellable(id: CancelID.debounce, cancelInFlight: true)

      case .presentAlert(let title, let message):
        state.alert = errorAlert(title: title, message: message)
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
  }

  private func periodicRefreshEffect() -> Effect<Action> {
    .run { send in
      while !Task.isCancelled {
        try await clock.sleep(for: GlobalConstants.worktreePeriodicRefreshInterval)
        await send(.periodicRefreshTick)
      }
    }
    .cancellable(id: CancelID.periodic, cancelInFlight: true)
  }

  private func loadRepositories(_ roots: [URL], animated: Bool) -> Effect<Action> {
    .run { send in
      let (repositories, errors) = await loadRepositoriesData(roots)
      await send(.repositoriesLoaded(repositories, errors: errors, animated: animated))
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private func loadRepositoriesData(_ roots: [URL]) async -> ([Repository], [String]) {
    var loaded: [Repository] = []
    var errors: [String] = []
    for root in roots {
      do {
        let worktrees = try await gitClient.worktrees(root)
        let name = repositoryName(from: root)
        let repository = Repository(
          id: root.standardizedFileURL.path(percentEncoded: false),
          rootURL: root.standardizedFileURL,
          name: name,
          worktrees: worktrees
        )
        loaded.append(repository)
      } catch {
        errors.append(error.localizedDescription)
      }
    }
    let persistedRoots = loaded.map { $0.rootURL.path(percentEncoded: false) }
    repositoryPersistence.saveRoots(persistedRoots)
    return (loaded, errors)
  }

  private func applyRepositories(_ repositories: [Repository], state: inout State, animated: Bool) {
    if animated {
      withAnimation {
        state.repositories = repositories
      }
    } else {
      state.repositories = repositories
    }
    if prunePinnedWorktreeIDs(state: &state) {
      repositoryPersistence.savePinnedWorktreeIDs(state.pinnedWorktreeIDs)
    }
    let repositoryIDs = Set(repositories.map(\.id))
    state.pendingWorktrees = state.pendingWorktrees.filter { repositoryIDs.contains($0.repositoryID) }
    let availableWorktreeIDs = Set(repositories.flatMap { $0.worktrees.map(\.id) })
    state.pendingSetupScriptWorktreeIDs = state.pendingSetupScriptWorktreeIDs.filter {
      availableWorktreeIDs.contains($0)
    }
    if !isSelectionValid(state.selectedWorktreeID, state: state) {
      state.selectedWorktreeID = nil
    }
    if state.selectedWorktreeID == nil, state.shouldSelectFirstAfterReload {
      state.selectedWorktreeID = firstAvailableWorktreeID(from: repositories, state: state)
      state.shouldSelectFirstAfterReload = false
    }
  }

  private func watcherEffects(
    previousWatching: Set<Repository.ID>,
    repositories: [Repository],
    state: inout State
  ) -> Effect<Action> {
    let currentIDs = Set(repositories.map(\.id))
    let removedIDs = previousWatching.subtracting(currentIDs)
    let addedRepos = repositories.filter { !previousWatching.contains($0.id) }
    state.watchingRepositoryIDs = currentIDs
    var effects: [Effect<Action>] = []
    for id in removedIDs {
      effects.append(.cancel(id: CancelID.watcher(id)))
    }
    for repository in addedRepos {
      effects.append(
        .run { send in
          let watch = await MainActor.run {
            repositoryWatcher.watch
          }
          for await _ in watch(repository.rootURL) {
            await send(.repositoryChangeDetected(repository.id))
          }
        }
        .cancellable(id: CancelID.watcher(repository.id))
      )
    }
    return .merge(effects)
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
        "This removes the repository from Supacode and deletes all of its worktrees "
          + "and their branches created by Supacode. "
          + "The main repository folder is not deleted."
      )
    }
  }
}

extension RepositoriesFeature.State {
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

  func selectedRow(for id: Worktree.ID?) -> WorktreeRowModel? {
    guard let id else { return nil }
    if let pending = pendingWorktree(for: id) {
      let isDeleting = removingRepositoryIDs.contains(pending.repositoryID)
      return WorktreeRowModel(
        id: pending.id,
        repositoryID: pending.repositoryID,
        name: pending.name,
        detail: pending.detail,
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

private func uniqueRootPaths(_ paths: [String]) -> [String] {
  var seen: Set<String> = []
  var unique: [String] = []
  for path in paths where seen.insert(path).inserted {
    unique.append(path)
  }
  return unique
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
