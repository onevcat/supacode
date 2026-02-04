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
      ["global.open-settings", "global.new-worktree"]
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
    #expect(ids.contains("worktree.\(keep.id).run"))
    #expect(ids.contains("worktree.\(keep.id).editor"))
    #expect(ids.contains("worktree.\(keep.id).archive"))
    #expect(ids.contains("worktree.\(keep.id).remove"))
    #expect(ids.contains { $0.contains(deleting.id) } == false)
    #expect(ids.contains { $0.contains("wt-pending") } == false)
  }

  @Test func commandPaletteItems_omitsArchiveAndRemoveForMainWorktree() {
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

  @Test func commandPaletteItems_includesArchiveAndRemoveForNonMainWorktree() {
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
        if case .removeWorktree(let worktreeID, let repositoryID) = $0.kind {
          return worktreeID == feature.id && repositoryID == repository.id
        }
        return false
      }
    )
    #expect(
      items.contains {
        if case .archiveWorktree(let worktreeID, let repositoryID) = $0.kind {
          return worktreeID == feature.id && repositoryID == repository.id
        }
        return false
      }
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
    let runFox = CommandPaletteItem(
      id: "worktree.fox.run",
      title: "Repo / fox",
      subtitle: "Run - main",
      kind: .runWorktree("wt-fox")
    )
    let editorFox = CommandPaletteItem(
      id: "worktree.fox.editor",
      title: "Repo / fox",
      subtitle: "Open in Editor - main",
      kind: .openWorktreeInEditor("wt-fox")
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
        items: [openSettings, newWorktree, selectFox, runFox, editorFox, archiveFox, removeFox],
        query: ""
      ),
      [openSettings, newWorktree]
    )
  }

  @Test func queryClearsSelectionWhenEmpty() async {
    var state = CommandPaletteFeature.State()
    state.query = "fox"
    state.selectedIndex = 1
    let store = TestStore(initialState: state) {
      CommandPaletteFeature()
    }

    await store.send(.binding(.set(\.query, ""))) {
      $0.query = ""
      $0.selectedIndex = nil
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

  @Test func activateDispatchesDelegate() async {
    var state = CommandPaletteFeature.State()
    state.isPresented = true
    state.query = "bear"
    state.selectedIndex = 1
    let store = TestStore(initialState: state) {
      CommandPaletteFeature()
    }

    await store.send(.activate(.runWorktree("wt-bear"))) {
      $0.isPresented = false
      $0.query = ""
      $0.selectedIndex = nil
    }
    await store.receive(.delegate(.runWorktree("wt-bear")))
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
