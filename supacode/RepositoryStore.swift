import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class RepositoryStore {
  private let userDefaults: UserDefaults
  private let gitClient: GitClient
  private let rootsKey = "repositories.roots"
  private let pinnedWorktreesKey = "repositories.worktrees.pinned"

  var repositories: [Repository] = []
  var selectedWorktreeID: String?
  var isOpenPanelPresented = false
  var openError: OpenRepositoryError?
  var createWorktreeError: CreateWorktreeError?
  var removeWorktreeError: RemoveWorktreeError?
  var removeRepositoryError: RemoveRepositoryError?
  var loadError: LoadRepositoryError?
  var pendingWorktrees: [PendingWorktree] = []
  var deletingWorktreeIDs: Set<Worktree.ID> = []
  var removingRepositoryIDs: Set<Repository.ID> = []
  private(set) var pinnedWorktreeIDs: [Worktree.ID] = []

  var canCreateWorktree: Bool {
    if repositories.isEmpty {
      return false
    }
    if let repository = repositoryForWorktreeCreation() {
      return !isRemovingRepository(repository)
    }
    return false
  }

  init(userDefaults: UserDefaults = .standard, gitClient: GitClient = .init()) {
    print("[RepositoryStore] init")
    self.userDefaults = userDefaults
    self.gitClient = gitClient
    pinnedWorktreeIDs = loadPinnedWorktreeIDs()
    print("[RepositoryStore] pinnedWorktreeIDs: \(pinnedWorktreeIDs)")
    Task {
      await loadPersistedRepositories()
    }
  }

  func loadPersistedRepositories() async {
    print("[RepositoryStore] loadPersistedRepositories started")
    let rootPaths = uniqueRootPaths(loadRootPaths())
    print("[RepositoryStore] rootPaths from UserDefaults: \(rootPaths)")
    let roots = rootPaths.map { URL(fileURLWithPath: $0) }
    let loaded = await loadRepositories(for: roots)
    print("[RepositoryStore] loaded \(loaded.count) repositories")
    applyRepositories(loaded)
    let persistedRoots = loaded.map { $0.rootURL.path(percentEncoded: false) }
    persistRootPaths(persistedRoots)
    print("[RepositoryStore] loadPersistedRepositories completed")
  }

  func openRepositories(at urls: [URL]) async {
    let existingRootPaths = uniqueRootPaths(loadRootPaths())
    var resolvedRoots: [URL] = []
    var failures: [String] = []

    for url in urls {
      do {
        let root = try await gitClient.repoRoot(for: url)
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
    let mergedRoots = uniqueRootPaths(mergedPaths).map { URL(fileURLWithPath: $0) }
    let loaded = await loadRepositories(for: mergedRoots)
    applyRepositories(loaded)
    let persistedRoots = loaded.map { $0.rootURL.path(percentEncoded: false) }
    persistRootPaths(persistedRoots)

    if !failures.isEmpty {
      let message = failures.map { "\($0) is not a Git repository." }.joined(separator: "\n")
      openError = OpenRepositoryError(
        id: UUID(),
        title: "Some folders couldn't be opened",
        message: message
      )
    }
  }

  func createRandomWorktree() async {
    createWorktreeError = nil
    guard let repository = repositoryForWorktreeCreation() else {
      let message: String
      if repositories.isEmpty {
        message = "Open a repository to create a worktree."
      } else if selectedWorktreeID == nil && repositories.count > 1 {
        message = "Select a worktree to choose which repository to use."
      } else {
        message = "Unable to resolve a repository for the new worktree."
      }
      createWorktreeError = CreateWorktreeError(
        id: UUID(),
        title: "Unable to create worktree",
        message: message
      )
      return
    }
    if isRemovingRepository(repository) {
      createWorktreeError = CreateWorktreeError(
        id: UUID(),
        title: "Unable to create worktree",
        message: "This repository is being removed."
      )
      return
    }

    await createRandomWorktree(in: repository)
  }

  func createRandomWorktree(in repository: Repository) async {
    createWorktreeError = nil
    if isRemovingRepository(repository) {
      createWorktreeError = CreateWorktreeError(
        id: UUID(),
        title: "Unable to create worktree",
        message: "This repository is being removed."
      )
      return
    }
    let previousSelection = selectedWorktreeID
    let pendingID = "pending:\(UUID().uuidString)"
    let pendingWorktree = PendingWorktree(
      id: pendingID,
      repositoryID: repository.id,
      name: "Creating worktree...",
      detail: ""
    )
    pendingWorktrees.append(pendingWorktree)
    selectedWorktreeID = pendingID
    do {
      let branchNames = try await gitClient.localBranchNames(for: repository.rootURL)
      let worktreeNames = Set(repository.worktrees.map { $0.name.lowercased() })
      let existing = worktreeNames.union(branchNames)
      guard let name = WorktreeNameGenerator.nextName(excluding: existing) else {
        removePendingWorktree(id: pendingID)
        restoreSelection(previousSelection, whenSelectionIs: pendingID)
        createWorktreeError = CreateWorktreeError(
          id: UUID(),
          title: "No available worktree names",
          message:
            "All default animal names are already in use. "
            + "Delete a worktree or rename a branch, then try again."
        )
        return
      }

      let newWorktree = try await gitClient.createWorktree(named: name, in: repository.rootURL)
      let roots = repositories.map(\.rootURL)
      let loaded = await loadRepositories(for: roots)
      if selectedWorktreeID == pendingID {
        selectedWorktreeID = newWorktree.id
      }
      removePendingWorktree(id: pendingID)
      applyRepositories(loaded)
    } catch {
      removePendingWorktree(id: pendingID)
      restoreSelection(previousSelection, whenSelectionIs: pendingID)
      createWorktreeError = CreateWorktreeError(
        id: UUID(),
        title: "Unable to create worktree",
        message: error.localizedDescription
      )
    }
  }

  func selectWorktree(_ id: String?) {
    selectedWorktreeID = id
  }

  func worktree(for id: String?) -> Worktree? {
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

  func pendingWorktrees(in repository: Repository) -> [PendingWorktree] {
    pendingWorktrees.filter { $0.repositoryID == repository.id }
  }

  func worktreeRows(in repository: Repository) -> [WorktreeRowModel] {
    let ordered = orderedWorktrees(in: repository)
    let pinnedIDs = Set(pinnedWorktreeIDs)
    let isRemovingRepository = removingRepositoryIDs.contains(repository.id)
    let pinnedWorktrees = ordered.filter { pinnedIDs.contains($0.id) }
    let unpinnedWorktrees = ordered.filter { !pinnedIDs.contains($0.id) }
    let pendingEntries = pendingWorktrees.filter { $0.repositoryID == repository.id }
    var rows: [WorktreeRowModel] = []
    for worktree in pinnedWorktrees {
      let isDeleting = isRemovingRepository || deletingWorktreeIDs.contains(worktree.id)
      rows.append(
        WorktreeRowModel(
          id: worktree.id,
          repositoryID: repository.id,
          name: worktree.name,
          detail: worktree.detail,
          isPinned: true,
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
          isPending: true,
          isDeleting: isRemovingRepository,
          isRemovable: false
        )
      )
    }
    for worktree in unpinnedWorktrees {
      let isDeleting = isRemovingRepository || deletingWorktreeIDs.contains(worktree.id)
      rows.append(
        WorktreeRowModel(
          id: worktree.id,
          repositoryID: repository.id,
          name: worktree.name,
          detail: worktree.detail,
          isPinned: false,
          isPending: false,
          isDeleting: isDeleting,
          isRemovable: !isDeleting
        )
      )
    }
    return rows
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

  func orderedWorktrees(in repository: Repository) -> [Worktree] {
    if pinnedWorktreeIDs.isEmpty {
      return repository.worktrees
    }
    let worktreeByID = Dictionary(uniqueKeysWithValues: repository.worktrees.map { ($0.id, $0) })
    var ordered: [Worktree] = []
    var seen: Set<Worktree.ID> = []
    for id in pinnedWorktreeIDs {
      if let worktree = worktreeByID[id] {
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

  func pinWorktree(_ worktree: Worktree) {
    pinnedWorktreeIDs.removeAll { $0 == worktree.id }
    pinnedWorktreeIDs.insert(worktree.id, at: 0)
    persistPinnedWorktreeIDs()
  }

  func unpinWorktree(_ worktree: Worktree) {
    pinnedWorktreeIDs.removeAll { $0 == worktree.id }
    persistPinnedWorktreeIDs()
  }

  func isWorktreeDirty(_ worktree: Worktree) async -> Bool {
    do {
      return try await gitClient.isWorktreeDirty(at: worktree.workingDirectory)
    } catch {
      removeWorktreeError = RemoveWorktreeError(
        id: UUID(),
        title: "Unable to check worktree status",
        message: error.localizedDescription
      )
      return true
    }
  }

  func removeWorktree(_ worktree: Worktree, from repository: Repository, force: Bool) async {
    removeWorktreeError = nil
    if deletingWorktreeIDs.contains(worktree.id) {
      return
    }
    deletingWorktreeIDs.insert(worktree.id)
    defer { deletingWorktreeIDs.remove(worktree.id) }
    let selectionWasRemoved = selectedWorktreeID == worktree.id
    let nextSelection = selectionWasRemoved ? nextWorktreeID(afterRemoving: worktree) : nil
    do {
      _ = try await gitClient.removeWorktree(
        named: worktree.name, in: repository.rootURL, force: force)
      let roots = repositories.map(\.rootURL)
      let loaded = await loadRepositories(for: roots)
      applyRepositories(loaded, animated: true)
      if selectionWasRemoved {
        selectedWorktreeID = nextSelection ?? firstAvailableWorktreeID(from: repositories)
      }
    } catch {
      removeWorktreeError = RemoveWorktreeError(
        id: UUID(),
        title: "Unable to remove worktree",
        message: error.localizedDescription
      )
    }
  }

  func removeRepository(_ repository: Repository) async {
    removeRepositoryError = nil
    if removingRepositoryIDs.contains(repository.id) {
      return
    }
    removingRepositoryIDs.insert(repository.id)
    defer { removingRepositoryIDs.remove(repository.id) }
    let selectionWasRemoved =
      selectedWorktreeID.map { id in
        repository.worktrees.contains(where: { $0.id == id })
      } ?? false
    var failures: [String] = []
    for worktree in repository.worktrees {
      do {
        _ = try await gitClient.removeWorktree(
          named: worktree.name,
          in: repository.rootURL,
          force: true
        )
      } catch {
        failures.append(error.localizedDescription)
      }
    }
    if failures.isEmpty {
      let rootPaths = uniqueRootPaths(loadRootPaths())
      let normalized = repository.rootURL.standardizedFileURL.path(percentEncoded: false)
      let remaining = rootPaths.filter { $0 != normalized }
      persistRootPaths(remaining)
    }
    let roots = uniqueRootPaths(loadRootPaths()).map { URL(fileURLWithPath: $0) }
    let loaded = await loadRepositories(for: roots)
    applyRepositories(loaded, animated: true)
    if selectionWasRemoved {
      selectedWorktreeID = firstAvailableWorktreeID(from: repositories)
    }
    if !failures.isEmpty {
      let message = failures.joined(separator: "\n")
      removeRepositoryError = RemoveRepositoryError(
        id: UUID(),
        title: "Unable to remove repository",
        message: message
      )
    }
  }

  private func repositoryForWorktreeCreation() -> Repository? {
    if let selectedWorktreeID {
      if let pending = pendingWorktree(for: selectedWorktreeID) {
        return repositories.first(where: { $0.id == pending.repositoryID })
      }
      for repository in repositories
      where repository.worktrees.contains(where: { $0.id == selectedWorktreeID }) {
        return repository
      }
    }
    if repositories.count == 1 {
      return repositories.first
    }
    return nil
  }

  private func isSelectionValid(_ id: Worktree.ID?) -> Bool {
    selectedRow(for: id) != nil
  }

  private func removePendingWorktree(id: String) {
    pendingWorktrees.removeAll { $0.id == id }
  }

  private func restoreSelection(_ id: Worktree.ID?, whenSelectionIs pendingID: Worktree.ID) {
    guard selectedWorktreeID == pendingID else { return }
    if isSelectionValid(id) {
      selectedWorktreeID = id
    } else {
      selectedWorktreeID = nil
    }
  }

  private func loadRootPaths() -> [String] {
    guard let data = userDefaults.data(forKey: rootsKey) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  private func uniqueRootPaths(_ paths: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for path in paths where seen.insert(path).inserted {
      unique.append(path)
    }
    return unique
  }

  private func persistRootPaths(_ roots: [String]) {
    guard let data = try? JSONEncoder().encode(roots) else { return }
    userDefaults.set(data, forKey: rootsKey)
  }

  private func loadPinnedWorktreeIDs() -> [Worktree.ID] {
    guard let data = userDefaults.data(forKey: pinnedWorktreesKey) else { return [] }
    return (try? JSONDecoder().decode([Worktree.ID].self, from: data)) ?? []
  }

  private func persistPinnedWorktreeIDs() {
    guard let data = try? JSONEncoder().encode(pinnedWorktreeIDs) else { return }
    userDefaults.set(data, forKey: pinnedWorktreesKey)
  }

  private func applyRepositories(_ loaded: [Repository], animated: Bool = false) {
    print("[RepositoryStore] applyRepositories: \(loaded.count) repositories")
    for repo in loaded {
      print("[RepositoryStore]   - \(repo.name): \(repo.worktrees.count) worktrees")
    }
    if animated {
      withAnimation {
        repositories = loaded
      }
    } else {
      repositories = loaded
    }
    prunePinnedWorktreeIDs(using: loaded)
    let repositoryIDs = Set(loaded.map(\.id))
    pendingWorktrees = pendingWorktrees.filter { repositoryIDs.contains($0.repositoryID) }
    if !isSelectionValid(selectedWorktreeID) {
      print(
        "[RepositoryStore] selectedWorktreeID \(String(describing: selectedWorktreeID)) is invalid, clearing"
      )
      selectedWorktreeID = nil
    }
    print("[RepositoryStore] applyRepositories done, repositories.count = \(repositories.count)")
  }

  private func prunePinnedWorktreeIDs(using repositories: [Repository]) {
    let availableIDs = Set(repositories.flatMap { $0.worktrees.map(\.id) })
    let pruned = pinnedWorktreeIDs.filter { availableIDs.contains($0) }
    if pruned != pinnedWorktreeIDs {
      pinnedWorktreeIDs = pruned
      persistPinnedWorktreeIDs()
    }
  }

  private func firstAvailableWorktreeID(from repositories: [Repository]) -> Worktree.ID? {
    for repository in repositories {
      if let first = orderedWorktrees(in: repository).first {
        return first.id
      }
    }
    return nil
  }

  private func nextWorktreeID(afterRemoving worktree: Worktree) -> Worktree.ID? {
    let orderedIDs = repositories.flatMap { repository in
      orderedWorktrees(in: repository).map(\.id)
    }
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

  private func loadRepositories(for roots: [URL]) async -> [Repository] {
    print("[RepositoryStore] loadRepositories for \(roots.count) roots")
    var loaded: [Repository] = []
    for root in roots {
      print("[RepositoryStore] loading root: \(root.path(percentEncoded: false))")
      do {
        let worktrees = try await gitClient.worktrees(for: root)
        print("[RepositoryStore] found \(worktrees.count) worktrees in \(root.lastPathComponent)")
        let name = repositoryName(from: root)
        let githubOwner = await gitClient.githubOwner(for: root)
        let repository = Repository(
          id: root.standardizedFileURL.path(percentEncoded: false),
          rootURL: root.standardizedFileURL,
          name: name,
          initials: repositoryInitials(from: name),
          githubOwner: githubOwner,
          worktrees: worktrees
        )
        loaded.append(repository)
        print("[RepositoryStore] loaded repository: \(name) with \(worktrees.count) worktrees")
      } catch {
        print("[RepositoryStore] ERROR loading \(root.path(percentEncoded: false)): \(error)")
        loadError = LoadRepositoryError(
          id: UUID(),
          title: "Failed to load repository",
          message: error.localizedDescription
        )
        continue
      }
    }
    return loaded
  }

  private func repositoryName(from root: URL) -> String {
    let name = root.lastPathComponent
    if name.isEmpty {
      return root.path(percentEncoded: false)
    }
    return name
  }

  private func repositoryInitials(from name: String) -> String {
    var parts: [String] = []
    var current = ""
    for character in name {
      if character.isLetter || character.isNumber {
        current.append(character)
      } else if !current.isEmpty {
        parts.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      parts.append(current)
    }
    let initials: String
    if parts.count >= 2 {
      let first = parts[0].prefix(1)
      let second = parts[1].prefix(1)
      initials = String(first + second)
    } else if let part = parts.first {
      initials = String(part.prefix(2))
    } else {
      initials = String(name.prefix(2))
    }
    return initials.uppercased()
  }
}
