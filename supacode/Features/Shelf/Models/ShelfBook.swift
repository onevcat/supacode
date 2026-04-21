import Foundation

/// A book on the Shelf — the unified abstraction over a Git worktree or
/// a plain folder repository.
///
/// For worktrees the `id` is the underlying `Worktree.ID`. For plain
/// folders the `id` is the owning `Repository.ID`; plain folders are
/// represented in the terminal system as synthetic worktrees sharing the
/// repository's ID, so using the repository ID here keeps it consistent
/// with `selectedTerminalWorktree?.id`.
struct ShelfBook: Identifiable, Equatable, Hashable, Sendable {
  enum Kind: Equatable, Hashable, Sendable {
    case worktree
    case plainFolder
  }

  let id: Worktree.ID
  let repositoryID: Repository.ID
  let displayName: String
  /// Project/repository name shown as the primary part of the spine
  /// header. For plain folders this equals the folder name.
  let projectName: String
  let branchName: String?
  let kind: Kind

  var isPlainFolder: Bool { kind == .plainFolder }
}

extension RepositoriesFeature.State {
  /// Books rendered on the Shelf, in the same order the left navigation
  /// presents them (by repository, then by worktree rows within the
  /// repository). Plain folder repositories contribute a single book.
  ///
  /// The list is filtered to only books whose IDs are in
  /// `openedWorktreeIDs` — a worktree (or plain folder) appears on the
  /// Shelf only after the user has interacted with it at least once.
  /// Clicking a previously-unopened worktree in the left navigation
  /// while in Shelf mode adds its ID here, which causes its spine to
  /// materialize (with the standard spine-flow animation).
  func orderedShelfBooks() -> [ShelfBook] {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    var books: [ShelfBook] = []
    for repositoryID in orderedRepositoryIDs() {
      guard let repository = repositoriesByID[repositoryID] else { continue }
      if repository.kind == .plain {
        guard openedWorktreeIDs.contains(repository.id) else { continue }
        books.append(
          ShelfBook(
            id: repository.id,
            repositoryID: repository.id,
            displayName: repository.name,
            projectName: repository.name,
            branchName: nil,
            kind: .plainFolder
          ))
        continue
      }
      for row in worktreeRows(in: repository) {
        guard openedWorktreeIDs.contains(row.id) else { continue }
        books.append(
          ShelfBook(
            id: row.id,
            repositoryID: repositoryID,
            displayName: row.name,
            projectName: repository.name,
            branchName: row.name,
            kind: .worktree
          ))
      }
    }
    return books
  }

  /// Identifier of the book currently open on the Shelf, derived from the
  /// active selection. Equal to `selectedTerminalWorktree?.id`, but kept as
  /// its own property so call sites read as shelf-aware.
  var openShelfBookID: Worktree.ID? {
    selectedTerminalWorktree?.id
  }
}
