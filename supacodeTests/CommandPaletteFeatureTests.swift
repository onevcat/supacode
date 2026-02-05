import ComposableArchitecture
import CustomDump
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct CommandPaletteFeatureTests {
  @Test func commandPaletteItems_onlyGlobalWhenEmpty() {
    let items = CommandPaletteFeature.commandPaletteItems(from: RepositoriesFeature.State())
    expectNoDifference(
      items.map(\.id),
      [
        "global.check-for-updates",
        "global.open-settings",
        "global.open-repository",
        "global.new-worktree",
        "global.refresh-worktrees",
      ]
    )
  }

  @Test func commandPaletteItems_skipsPendingAndDeletingWorktrees() {
    let rootPath = "/tmp/repo"
    let keep = makeWorktree(id: "\(rootPath)/wt-keep", name: "keep", repoRoot: rootPath)
    let deleting = makeWorktree(
      id: "\(rootPath)/wt-delete",
      name: "delete",
      repoRoot: rootPath
    )
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [keep, deleting])
    var state = RepositoriesFeature.State(repositories: [repository])
    state.deletingWorktreeIDs = [deleting.id]
    state.pendingWorktrees = [
      PendingWorktree(
        id: "\(rootPath)/wt-pending",
        repositoryID: repository.id,
        name: "pending",
        detail: "pending"
      ),
    ]

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let ids = items.map(\.id)
    #expect(ids.contains("worktree.\(keep.id).select"))
    #expect(ids.contains { $0.contains(deleting.id) } == false)
    #expect(ids.contains { $0.contains("wt-pending") } == false)
  }

  @Test func commandPaletteItems_omitsSubActionsForMainWorktree() {
    let rootPath = "/tmp/repo"
    let main = makeWorktree(
      id: rootPath,
      name: "repo",
      detail: "main",
      repoRoot: rootPath,
      workingDirectory: rootPath
    )
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [main])
    let items = CommandPaletteFeature.commandPaletteItems(
      from: RepositoriesFeature.State(repositories: [repository])
    )

    #expect(
      items.contains {
        if case .removeWorktree = $0.kind {
          return true
        }
        return false
      } == false
    )
    #expect(
      items.contains {
        if case .archiveWorktree = $0.kind {
          return true
        }
        return false
      } == false
    )
    #expect(
      items.filter {
        if case .worktreeSelect = $0.kind {
          return true
        }
        return false
      }.count == 1
    )
  }

  @Test func commandPaletteItems_omitsSubActionsForNonMainWorktree() {
    let rootPath = "/tmp/repo"
    let main = makeWorktree(
      id: rootPath,
      name: "repo",
      detail: "main",
      repoRoot: rootPath,
      workingDirectory: rootPath
    )
    let feature = makeWorktree(
      id: "\(rootPath)/wt-feature",
      name: "feature",
      detail: "feature",
      repoRoot: rootPath
    )
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [main, feature])
    let items = CommandPaletteFeature.commandPaletteItems(
      from: RepositoriesFeature.State(repositories: [repository])
    )

    #expect(
      items.contains {
        if case .removeWorktree = $0.kind {
          return true
        }
        return false
      } == false
    )
    #expect(
      items.contains {
        if case .archiveWorktree = $0.kind {
          return true
        }
        return false
      } == false
    )
  }

  @Test func commandPaletteItems_trimsDetailToNil() {
    let rootPath = "/tmp/repo"
    let worktree = makeWorktree(
      id: "\(rootPath)/wt-detail",
      name: "detail",
      detail: "   ",
      repoRoot: rootPath
    )
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [worktree])
    let items = CommandPaletteFeature.commandPaletteItems(
      from: RepositoriesFeature.State(repositories: [repository])
    )
    let selectItem = items.first {
      if case .worktreeSelect(let id) = $0.kind {
        return id == worktree.id
      }
      return false
    }
    #expect(selectItem?.subtitle == nil)
  }

  @Test func commandPaletteItems_keepsFullWorktreeName() {
    let rootPath = "/tmp/repo"
    let worktree = makeWorktree(
      id: "\(rootPath)/wt-path",
      name: "khoi/cache",
      detail: "main",
      repoRoot: rootPath
    )
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [worktree])
    let items = CommandPaletteFeature.commandPaletteItems(
      from: RepositoriesFeature.State(repositories: [repository])
    )
    let selectItem = items.first {
      if case .worktreeSelect(let id) = $0.kind {
        return id == worktree.id
      }
      return false
    }
    #expect(selectItem?.title == "Repo / khoi/cache")
  }

  @Test func commandPaletteItems_respectsRowOrderWithinRepository() {
    let rootPath = "/tmp/repo"
    let main = makeWorktree(
      id: rootPath,
      name: "repo",
      detail: "main",
      repoRoot: rootPath,
      workingDirectory: rootPath
    )
    let pinned = makeWorktree(
      id: "\(rootPath)/wt-pinned",
      name: "pinned",
      detail: "pinned",
      repoRoot: rootPath
    )
    let unpinned = makeWorktree(
      id: "\(rootPath)/wt-unpinned",
      name: "unpinned",
      detail: "unpinned",
      repoRoot: rootPath
    )
    let repository = makeRepository(
      rootPath: rootPath, name: "Repo",
      worktrees: [
        main,
        pinned,
        unpinned,
      ])
    var state = RepositoriesFeature.State(repositories: [repository])
    state.pinnedWorktreeIDs = [pinned.id]
    state.worktreeOrderByRepository = [repository.id: [unpinned.id]]

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let selectIDs = items.compactMap { item in
      if case .worktreeSelect(let id) = item.kind {
        return id
      }
      return nil
    }
    expectNoDifference(selectIDs, [main.id, pinned.id, unpinned.id])
  }

  @Test func commandPaletteItems_respectsRepositoryOrder() {
    let repoAPath = "/tmp/repo-a"
    let repoBPath = "/tmp/repo-b"
    let mainA = makeWorktree(
      id: repoAPath,
      name: "repo-a",
      detail: "main",
      repoRoot: repoAPath,
      workingDirectory: repoAPath
    )
    let mainB = makeWorktree(
      id: repoBPath,
      name: "repo-b",
      detail: "main",
      repoRoot: repoBPath,
      workingDirectory: repoBPath
    )
    let repoA = makeRepository(rootPath: repoAPath, name: "Repo A", worktrees: [mainA])
    let repoB = makeRepository(rootPath: repoBPath, name: "Repo B", worktrees: [mainB])
    var state = RepositoriesFeature.State(repositories: [repoA, repoB])
    state.repositoryRoots = [repoB.rootURL, repoA.rootURL]

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let selectIDs = items.compactMap { item in
      if case .worktreeSelect(let id) = item.kind {
        return id
      }
      return nil
    }
    expectNoDifference(selectIDs, [mainB.id, mainA.id])
  }

  @Test func showsGlobalItemsWhenQueryEmpty() {
    let openSettings = CommandPaletteItem(
      id: "global.open-settings",
      title: "Open Settings",
      subtitle: nil,
      kind: .openSettings
    )
    let newWorktree = CommandPaletteItem(
      id: "global.new-worktree",
      title: "New Worktree",
      subtitle: nil,
      kind: .newWorktree
    )
    let selectFox = CommandPaletteItem(
      id: "worktree.fox.select",
      title: "Repo / fox",
      subtitle: "main",
      kind: .worktreeSelect("wt-fox")
    )
    let archiveFox = CommandPaletteItem(
      id: "worktree.fox.archive",
      title: "Repo / fox",
      subtitle: "Archive Worktree - main",
      kind: .archiveWorktree("wt-fox", "repo-fox")
    )
    let removeFox = CommandPaletteItem(
      id: "worktree.fox.remove",
      title: "Repo / fox",
      subtitle: "Remove Worktree - main",
      kind: .removeWorktree("wt-fox", "repo-fox")
    )

    expectNoDifference(
      CommandPaletteFeature.filterItems(
        items: [openSettings, newWorktree, selectFox, archiveFox, removeFox],
        query: ""
      ),
      [openSettings, newWorktree]
    )
  }

  @Test func queryKeepsSelectionWhenEmpty() async {
    var state = CommandPaletteFeature.State()
    state.query = "fox"
    state.selectedIndex = 1
    let store = TestStore(initialState: state) {
      CommandPaletteFeature()
    }

    await store.send(.binding(.set(\.query, ""))) {
      $0.query = ""
      $0.selectedIndex = 1
    }
  }

  @Test func queryMatchesGlobalItemsBeforeWorktrees() {
    let openSettings = CommandPaletteItem(
      id: "global.open-settings",
      title: "Open Settings",
      subtitle: nil,
      kind: .openSettings
    )
    let selectSettings = CommandPaletteItem(
      id: "worktree.settings.select",
      title: "Repo / settings",
      subtitle: "main",
      kind: .worktreeSelect("wt-settings")
    )

    expectNoDifference(
      CommandPaletteFeature.filterItems(items: [selectSettings, openSettings], query: "set"),
      [openSettings, selectSettings]
    )
  }

  @Test func fuzzyRanksPrefixAndShorterLabelFirst() {
    let short = CommandPaletteItem(
      id: "worktree.set.select",
      title: "Set",
      subtitle: nil,
      kind: .worktreeSelect("wt-set")
    )
    let long = CommandPaletteItem(
      id: "worktree.settings.select",
      title: "Settings",
      subtitle: nil,
      kind: .worktreeSelect("wt-settings")
    )

    expectNoDifference(
      CommandPaletteFeature.filterItems(items: [long, short], query: "set"),
      [short, long]
    )
  }

  @Test func fuzzyMatchesSubtitleWhenLabelDoesNot() {
    let item = CommandPaletteItem(
      id: "worktree.fox.select",
      title: "Repo / fox",
      subtitle: "main",
      kind: .worktreeSelect("wt-fox")
    )

    expectNoDifference(
      CommandPaletteFeature.filterItems(items: [item], query: "main"),
      [item]
    )
  }

  @Test func fuzzyMatchesMultiplePieces() {
    let item = CommandPaletteItem(
      id: "worktree.fox.select",
      title: "Repo / fox",
      subtitle: "main",
      kind: .worktreeSelect("wt-fox")
    )

    expectNoDifference(
      CommandPaletteFeature.filterItems(items: [item], query: "repo main"),
      [item]
    )
  }

  @Test func commandPaletteDraftActionRanksFirst() {
    let rootPath = "/tmp/repo"
    let worktree = makeWorktree(id: "\(rootPath)/wt-draft", name: "draft", repoRoot: rootPath)
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [worktree])
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.worktreeInfoByID[worktree.id] = WorktreeInfoEntry(
      addedLines: nil,
      removedLines: nil,
      pullRequest: makePullRequest(isDraft: true)
    )

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let ordered = CommandPaletteFeature.filterItems(items: items, query: "")
    #expect(ordered.first?.title == "Mark PR Ready for Review")
  }

  @Test func commandPaletteFailingActionRanksFirst() {
    let rootPath = "/tmp/repo"
    let worktree = makeWorktree(id: "\(rootPath)/wt-failing", name: "failing", repoRoot: rootPath)
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [worktree])
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    let failingCheck = GithubPullRequestStatusCheck(
      status: "COMPLETED",
      conclusion: "FAILURE",
      state: nil
    )
    state.worktreeInfoByID[worktree.id] = WorktreeInfoEntry(
      addedLines: nil,
      removedLines: nil,
      pullRequest: makePullRequest(checks: [failingCheck])
    )

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let ordered = CommandPaletteFeature.filterItems(items: items, query: "")
    #expect(ordered.first?.title == "Copy CI Failure Logs")
  }

  @Test func commandPaletteMergeActionRanksFirstWhenMergeable() {
    let rootPath = "/tmp/repo"
    let worktree = makeWorktree(id: "\(rootPath)/wt-merge", name: "merge", repoRoot: rootPath)
    let repository = makeRepository(rootPath: rootPath, name: "Repo", worktrees: [worktree])
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.worktreeInfoByID[worktree.id] = WorktreeInfoEntry(
      addedLines: nil,
      removedLines: nil,
      pullRequest: makePullRequest(
        mergeable: "MERGEABLE",
        mergeStateStatus: "CLEAN"
      )
    )

    let items = CommandPaletteFeature.commandPaletteItems(from: state)
    let ordered = CommandPaletteFeature.filterItems(items: items, query: "")
    #expect(ordered.first?.title == "Merge Ready")
  }

  @Test func recencyBreaksFuzzyTiesWithinGroup() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let recent = CommandPaletteItem(
      id: "global.recent",
      title: "Open",
      subtitle: nil,
      kind: .openRepository
    )
    let older = CommandPaletteItem(
      id: "global.older",
      title: "Open",
      subtitle: nil,
      kind: .openSettings
    )
    let recency: [CommandPaletteItem.ID: TimeInterval] = [
      recent.id: now.timeIntervalSince1970 - 1 * 86_400,
      older.id: now.timeIntervalSince1970 - 10 * 86_400,
    ]

    expectNoDifference(
      CommandPaletteFeature.filterItems(
        items: [older, recent],
        query: "open",
        recencyByID: recency,
        now: now
      ),
      [recent, older]
    )
  }

  @Test func activateDispatchesDelegateAndUpdatesRecency() async {
    var state = CommandPaletteFeature.State()
    state.isPresented = true
    state.query = "bear"
    state.selectedIndex = 1
    let item = CommandPaletteItem(
      id: "global.open-repository",
      title: "Open Repository",
      subtitle: nil,
      kind: .openRepository
    )
    let store = TestStore(initialState: state) {
      CommandPaletteFeature()
    }
    let now = Date(timeIntervalSince1970: 1_234_567)
    store.dependencies.date = .constant(now)

    await store.send(.activateItem(item)) {
      $0.isPresented = false
      $0.query = ""
      $0.selectedIndex = nil
      $0.recencyByItemID[item.id] = now.timeIntervalSince1970
    }
    await store.receive(.delegate(.openRepository))
  }
}

private func makeWorktree(
  id: String,
  name: String,
  detail: String = "detail",
  repoRoot: String,
  workingDirectory: String? = nil
) -> Worktree {
  Worktree(
    id: id,
    name: name,
    detail: detail,
    workingDirectory: URL(fileURLWithPath: workingDirectory ?? id),
    repositoryRootURL: URL(fileURLWithPath: repoRoot)
  )
}

private func makeRepository(
  rootPath: String,
  name: String,
  worktrees: [Worktree]
) -> Repository {
  let rootURL = URL(fileURLWithPath: rootPath)
  return Repository(
    id: rootURL.path(percentEncoded: false),
    rootURL: rootURL,
    name: name,
    worktrees: IdentifiedArray(uniqueElements: worktrees)
  )
}

private func makePullRequest(
  state: String = "OPEN",
  isDraft: Bool = false,
  reviewDecision: String? = nil,
  mergeable: String? = nil,
  mergeStateStatus: String? = nil,
  checks: [GithubPullRequestStatusCheck] = []
) -> GithubPullRequest {
  GithubPullRequest(
    number: 1,
    title: "PR",
    state: state,
    additions: 0,
    deletions: 0,
    isDraft: isDraft,
    reviewDecision: reviewDecision,
    mergeable: mergeable,
    mergeStateStatus: mergeStateStatus,
    updatedAt: nil,
    url: "https://example.com/pull/1",
    headRefName: "feature",
    statusCheckRollup: checks.isEmpty ? nil : GithubPullRequestStatusCheckRollup(checks: checks)
  )
}
