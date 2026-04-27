import ComposableArchitecture
import SwiftUI

extension RepositoriesFeature {
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func reduceWorktreeOrdering(
    state: inout State,
    action: WorktreeOrderingAction
  ) -> Effect<Action> {
    switch action {
    case .repositoriesMoved(let source, let destination):
      var orderedRepositoryIDs = state.orderedRepositoryIDs()
      orderedRepositoryIDs.move(fromOffsets: source, toOffset: destination)
      state.repositoryOrderIDs = orderedRepositoryIDs
      let repositoryOrderIDs = state.repositoryOrderIDs
      return .run { _ in
        await repositoryPersistence.saveRepositoryOrderIDs(repositoryOrderIDs)
      }

    case .pinnedWorktreesMoved(let repositoryID, let source, let destination):
      guard let repository = state.repositories[id: repositoryID] else {
        return .none
      }
      var orderedPinnedWorktreeIDs = state.orderedPinnedWorktreeIDs(in: repository)
      orderedPinnedWorktreeIDs.move(fromOffsets: source, toOffset: destination)
      state.pinnedWorktreeIDs = state.replacingPinnedWorktreeIDs(
        in: repository,
        with: orderedPinnedWorktreeIDs
      )
      let pinnedWorktreeIDs = state.pinnedWorktreeIDs
      return .run { _ in
        await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
      }

    case .unpinnedWorktreesMoved(let repositoryID, let source, let destination):
      guard let repository = state.repositories[id: repositoryID] else {
        return .none
      }
      var orderedUnpinnedWorktreeIDs = state.orderedUnpinnedWorktreeIDs(in: repository)
      orderedUnpinnedWorktreeIDs.move(fromOffsets: source, toOffset: destination)
      if orderedUnpinnedWorktreeIDs.isEmpty {
        state.worktreeOrderByRepository.removeValue(forKey: repositoryID)
      } else {
        state.worktreeOrderByRepository[repositoryID] = orderedUnpinnedWorktreeIDs
      }
      let worktreeOrderByRepository = state.worktreeOrderByRepository
      return .run { _ in
        await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
      }

    case .pinWorktree(let worktreeID):
      if let worktree = state.worktree(for: worktreeID), state.isMainWorktree(worktree) {
        let wasPinned = state.pinnedWorktreeIDs.contains(worktreeID)
        state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
        var didUpdateWorktreeOrder = false
        if let repositoryID = state.repositoryID(containing: worktreeID),
          var order = state.worktreeOrderByRepository[repositoryID]
        {
          order.removeAll { $0 == worktreeID }
          if order.isEmpty {
            state.worktreeOrderByRepository.removeValue(forKey: repositoryID)
          } else {
            state.worktreeOrderByRepository[repositoryID] = order
          }
          didUpdateWorktreeOrder = true
        }
        var effects: [Effect<Action>] = []
        if wasPinned {
          let pinnedWorktreeIDs = state.pinnedWorktreeIDs
          effects.append(
            .run { _ in
              await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
            }
          )
        }
        if didUpdateWorktreeOrder {
          let worktreeOrderByRepository = state.worktreeOrderByRepository
          effects.append(
            .run { _ in
              await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
            }
          )
        }
        return .merge(effects)
      }
      analyticsClient.capture("worktree_pinned", [String: Any]?.none)
      state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
      state.pinnedWorktreeIDs.insert(worktreeID, at: 0)
      var didUpdateWorktreeOrder = false
      if let repositoryID = state.repositoryID(containing: worktreeID),
        var order = state.worktreeOrderByRepository[repositoryID]
      {
        order.removeAll { $0 == worktreeID }
        if order.isEmpty {
          state.worktreeOrderByRepository.removeValue(forKey: repositoryID)
        } else {
          state.worktreeOrderByRepository[repositoryID] = order
        }
        didUpdateWorktreeOrder = true
      }
      let pinnedWorktreeIDs = state.pinnedWorktreeIDs
      var effects: [Effect<Action>] = [
        .run { _ in
          await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
        }
      ]
      if didUpdateWorktreeOrder {
        let worktreeOrderByRepository = state.worktreeOrderByRepository
        effects.append(
          .run { _ in
            await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
          }
        )
      }
      return .merge(effects)

    case .unpinWorktree(let worktreeID):
      analyticsClient.capture("worktree_unpinned", [String: Any]?.none)
      state.pinnedWorktreeIDs.removeAll { $0 == worktreeID }
      var didUpdateWorktreeOrder = false
      if let repositoryID = state.repositoryID(containing: worktreeID) {
        var order = state.worktreeOrderByRepository[repositoryID] ?? []
        order.removeAll { $0 == worktreeID }
        order.insert(worktreeID, at: 0)
        state.worktreeOrderByRepository[repositoryID] = order
        didUpdateWorktreeOrder = true
      }
      let pinnedWorktreeIDs = state.pinnedWorktreeIDs
      var effects: [Effect<Action>] = [
        .run { _ in
          await repositoryPersistence.savePinnedWorktreeIDs(pinnedWorktreeIDs)
        }
      ]
      if didUpdateWorktreeOrder {
        let worktreeOrderByRepository = state.worktreeOrderByRepository
        effects.append(
          .run { _ in
            await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
          }
        )
      }
      return .merge(effects)

    case .worktreeNotificationReceived(let worktreeID):
      guard let repositoryID = state.repositoryID(containing: worktreeID),
        let repository = state.repositories[id: repositoryID],
        let worktree = repository.worktrees[id: worktreeID]
      else {
        return .none
      }
      if state.isWorktreeArchived(worktree.id) {
        return .none
      }
      if state.moveNotifiedWorktreeToTop, !state.isMainWorktree(worktree), !state.isWorktreePinned(worktree) {
        let reordered = reorderedUnpinnedWorktreeIDs(
          for: worktreeID,
          in: repository,
          state: state
        )
        if state.worktreeOrderByRepository[repositoryID] != reordered {
          withAnimation(.snappy(duration: 0.2)) {
            state.worktreeOrderByRepository[repositoryID] = reordered
          }
          let worktreeOrderByRepository = state.worktreeOrderByRepository
          return .run { _ in
            await repositoryPersistence.saveWorktreeOrderByRepository(worktreeOrderByRepository)
          }
        }
      }
      return .none

    case .setMoveNotifiedWorktreeToTop(let isEnabled):
      state.moveNotifiedWorktreeToTop = isEnabled
      return .none
    }
  }

  var worktreeOrderingReducer: some ReducerOf<Self> {
    Reduce { state, action in
      guard case .worktreeOrdering(let action) = action else {
        return .none
      }
      return reduceWorktreeOrdering(state: &state, action: action)
    }
  }
}
