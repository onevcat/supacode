import ComposableArchitecture
import Foundation

@Reducer
struct CommandPaletteFeature {
  @ObservableState
  struct State: Equatable {
    var isPresented = false
    var query = ""
    var selectedIndex: Int?
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case setPresented(Bool)
    case togglePresented
    case activate(CommandPaletteItem.Kind)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case selectWorktree(Worktree.ID)
    case openSettings
    case newWorktree
    case removeWorktree(Worktree.ID, Repository.ID)
    case archiveWorktree(Worktree.ID, Repository.ID)
    case runWorktree(Worktree.ID)
    case openWorktreeInEditor(Worktree.ID)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding(\.query):
        let trimmed = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          state.selectedIndex = nil
        }
        return .none

      case .binding:
        return .none

      case .setPresented(let isPresented):
        state.isPresented = isPresented
        if isPresented {
          state.selectedIndex = nil
        } else {
          state.query = ""
          state.selectedIndex = nil
        }
        return .none

      case .togglePresented:
        state.isPresented.toggle()
        if state.isPresented {
          state.selectedIndex = nil
        } else {
          state.query = ""
          state.selectedIndex = nil
        }
        return .none

      case .activate(let kind):
        state.isPresented = false
        state.query = ""
        state.selectedIndex = nil
        return .send(.delegate(delegateAction(for: kind)))

      case .delegate:
        return .none
      }
    }
  }

  static func filterItems(items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let globalItems = items.filter(\.isGlobal)
    guard !trimmed.isEmpty else { return globalItems }
    let worktreeItems = items.filter { !$0.isGlobal }
    let matcher: (CommandPaletteItem) -> Bool = { $0.matches(query: trimmed) }
    return globalItems.filter(matcher) + worktreeItems.filter(matcher)
  }

  static func commandPaletteItems(
    from repositories: RepositoriesFeature.State
  ) -> [CommandPaletteItem] {
    var items: [CommandPaletteItem] = [
      CommandPaletteItem(
        id: "global.open-settings",
        title: "Open Settings",
        subtitle: nil,
        kind: .openSettings
      ),
      CommandPaletteItem(
        id: "global.new-worktree",
        title: "New Worktree",
        subtitle: nil,
        kind: .newWorktree
      ),
    ]
    for row in repositories.orderedWorktreeRows() {
      guard !row.isPending, !row.isDeleting else { continue }
      let repositoryName = repositories.repositoryName(for: row.repositoryID) ?? "Repository"
      let title = "\(repositoryName) / \(row.name)"
      let trimmedDetail = row.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      let detail = trimmedDetail.isEmpty ? nil : trimmedDetail
      items.append(
        CommandPaletteItem(
          id: "worktree.\(row.id).select",
          title: title,
          subtitle: detail,
          kind: .worktreeSelect(row.id)
        )
      )
      items.append(
        CommandPaletteItem(
          id: "worktree.\(row.id).run",
          title: title,
          subtitle: detail,
          kind: .runWorktree(row.id)
        )
      )
      items.append(
        CommandPaletteItem(
          id: "worktree.\(row.id).editor",
          title: title,
          subtitle: detail,
          kind: .openWorktreeInEditor(row.id)
        )
      )
      if row.isRemovable, !row.isMainWorktree {
        items.append(
          CommandPaletteItem(
            id: "worktree.\(row.id).archive",
            title: title,
            subtitle: detail,
            kind: .archiveWorktree(row.id, row.repositoryID)
          )
        )
        items.append(
          CommandPaletteItem(
            id: "worktree.\(row.id).remove",
            title: title,
            subtitle: detail,
            kind: .removeWorktree(row.id, row.repositoryID)
          )
        )
      }
    }
    return items
  }
}

private func delegateAction(for kind: CommandPaletteItem.Kind) -> CommandPaletteFeature.Delegate {
  switch kind {
  case .worktreeSelect(let id):
    return .selectWorktree(id)
  case .openSettings:
    return .openSettings
  case .newWorktree:
    return .newWorktree
  case .removeWorktree(let worktreeID, let repositoryID):
    return .removeWorktree(worktreeID, repositoryID)
  case .archiveWorktree(let worktreeID, let repositoryID):
    return .archiveWorktree(worktreeID, repositoryID)
  case .runWorktree(let worktreeID):
    return .runWorktree(worktreeID)
  case .openWorktreeInEditor(let worktreeID):
    return .openWorktreeInEditor(worktreeID)
  }
}
