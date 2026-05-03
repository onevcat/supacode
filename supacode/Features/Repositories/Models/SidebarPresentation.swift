import Foundation

struct SidebarPresentation: Equatable {
  var items: [SidebarItem]

  static func showsListHeader(repositoryCount: Int) -> Bool {
    repositoryCount > 10
  }

  var repositoryOrderIDs: [Repository.ID] {
    items.compactMap(\.repositoryOrderID)
  }

  func repositoryOrderAfterMove(
    fromOffsets source: IndexSet,
    toOffset destination: Int
  ) -> [Repository.ID] {
    var orderedIDs = repositoryOrderIDs
    orderedIDs.moveElements(fromOffsets: source, toOffset: destination)
    return orderedIDs
  }
}

enum SidebarItem: Equatable, Identifiable {
  case listHeader(SidebarListHeaderModel)
  case repository(SidebarRepositoryContainerModel)
  case failedRepository(FailedRepositoryModel)
  case archivedWorktrees(ArchivedWorktreesRowModel)

  var id: SidebarPresentationItemID {
    switch self {
    case .listHeader:
      return .listHeader
    case .repository(let model):
      return .repository(model.id)
    case .failedRepository(let model):
      return .failedRepository(model.id)
    case .archivedWorktrees:
      return .archivedWorktrees
    }
  }

  var repositoryOrderID: Repository.ID? {
    switch self {
    case .repository(let model):
      return model.id
    case .failedRepository(let model) where model.isReorderable:
      return model.id
    case .listHeader, .failedRepository, .archivedWorktrees:
      return nil
    }
  }
}

enum SidebarPresentationItemID: Equatable, Hashable {
  case listHeader
  case repository(Repository.ID)
  case failedRepository(Repository.ID)
  case archivedWorktrees
}

enum SidebarScrollID: Equatable, Hashable {
  case repository(Repository.ID)
  case worktree(Worktree.ID)
  case archivedWorktrees
}

struct SidebarListHeaderModel: Equatable, Identifiable {
  let id = SidebarPresentationItemID.listHeader
  var repositoryCount: Int
}

struct SidebarRepositoryContainerModel: Equatable, Identifiable {
  var id: Repository.ID { repositoryID }

  var repositoryID: Repository.ID
  var title: String
  var rootURL: URL
  var kind: Repository.Kind
  var isExpanded: Bool
  var isRemoving: Bool
  var worktreeSections: WorktreeRowSections
}

struct FailedRepositoryModel: Equatable, Identifiable {
  var id: Repository.ID
  var name: String
  var path: String
  var failureMessage: String
  var isReorderable: Bool
}

struct ArchivedWorktreesRowModel: Equatable, Identifiable {
  let id = SidebarPresentationItemID.archivedWorktrees
  var count: Int
}

enum SidebarWorktreeSection: Equatable {
  case pinned
  case unpinned
}

struct SidebarWorktreeDropTarget: Equatable {
  var repositoryID: Repository.ID
  var section: SidebarWorktreeSection
  var source: IndexSet
  var destination: Int

  var action: RepositoriesFeature.WorktreeOrderingAction {
    switch section {
    case .pinned:
      return .pinnedWorktreesMoved(repositoryID: repositoryID, source, destination)
    case .unpinned:
      return .unpinnedWorktreesMoved(repositoryID: repositoryID, source, destination)
    }
  }
}

extension RepositoriesFeature.State {
  func sidebarPresentation(
    expandedRepositoryIDs: Set<Repository.ID>,
    includesArchivedWorktreesRow: Bool = false
  ) -> SidebarPresentation {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    let roots = sidebarPresentationRoots()
    let repositoryCount = roots.count
    var items: [SidebarItem] = []

    if SidebarPresentation.showsListHeader(repositoryCount: repositoryCount) {
      items.append(.listHeader(SidebarListHeaderModel(repositoryCount: repositoryCount)))
    }

    for rootURL in roots {
      let standardizedRootURL = rootURL.standardizedFileURL
      let repositoryID = standardizedRootURL.path(percentEncoded: false)
      if let failureMessage = loadFailuresByID[repositoryID] {
        let path = standardizedRootURL.path(percentEncoded: false)
        items.append(
          .failedRepository(
            FailedRepositoryModel(
              id: repositoryID,
              name: Repository.name(for: standardizedRootURL),
              path: path,
              failureMessage: failureMessage,
              isReorderable: true
            )
          )
        )
      } else if let repository = repositoriesByID[repositoryID] {
        let isExpanded = expandedRepositoryIDs.contains(repository.id)
        items.append(
          .repository(
            SidebarRepositoryContainerModel(
              repositoryID: repository.id,
              title: repository.name,
              rootURL: repository.rootURL,
              kind: repository.kind,
              isExpanded: isExpanded,
              isRemoving: isRemovingRepository(repository),
              worktreeSections: isExpanded ? worktreeRowSections(in: repository) : .empty
            )
          )
        )
      }
    }

    if includesArchivedWorktreesRow, !archivedWorktrees.isEmpty {
      items.append(.archivedWorktrees(ArchivedWorktreesRowModel(count: archivedWorktrees.count)))
    }

    return SidebarPresentation(items: items)
  }

  private func sidebarPresentationRoots() -> [URL] {
    let orderedRoots = orderedRepositoryRoots()
    if !orderedRoots.isEmpty {
      return orderedRoots
    }
    return repositories.map(\.rootURL)
  }
}

extension WorktreeRowSections {
  static let empty = WorktreeRowSections(
    main: nil,
    pinned: [],
    pending: [],
    unpinned: []
  )
}

extension Array {
  fileprivate mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
    let sourceIndexes = source.sorted()
    let movedElements = sourceIndexes.map { self[$0] }
    for index in sourceIndexes.reversed() {
      remove(at: index)
    }
    let removedBeforeDestination = sourceIndexes.filter { $0 < destination }.count
    insert(contentsOf: movedElements, at: destination - removedBeforeDestination)
  }
}
