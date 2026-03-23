import Foundation
import YiTong

@Observable
@MainActor
final class GitLogWindowState {
  var worktreeURL: URL?
  var branchName: String = ""

  var commits: [GitLogCommit] = []
  var isLoadingCommits = false
  var hasMoreCommits = true

  var selectedCommit: GitLogCommit?
  var commitFiles: [DiffChangedFile] = []
  var isLoadingDetail = false

  var selectedFile: DiffChangedFile?
  var diffDocument: DiffDocument?

  private var loadedCount = 0
  private var documentCache: [String: DiffDocument] = [:]
  private var loadTask: Task<Void, Never>?
  private var detailTask: Task<Void, Never>?

  private static let pageSize = 50

  func load(worktreeURL: URL, branchName: String) {
    self.worktreeURL = worktreeURL
    self.branchName = branchName
    commits = []
    selectedCommit = nil
    commitFiles = []
    selectedFile = nil
    diffDocument = nil
    documentCache = [:]
    loadedCount = 0
    hasMoreCommits = true
    loadTask?.cancel()
    detailTask?.cancel()
    loadTask = Task { await loadCommits(worktreeURL: worktreeURL, skip: 0) }
  }

  func loadMore() {
    guard !isLoadingCommits, hasMoreCommits, let worktreeURL else { return }
    loadTask?.cancel()
    loadTask = Task { await loadCommits(worktreeURL: worktreeURL, skip: loadedCount) }
  }

  func selectCommit(_ commit: GitLogCommit) {
    guard selectedCommit != commit else { return }
    selectedCommit = commit
    commitFiles = []
    selectedFile = nil
    diffDocument = nil
    documentCache = [:]
    detailTask?.cancel()
    guard let worktreeURL else { return }
    detailTask = Task { await loadCommitDetail(commit: commit, worktreeURL: worktreeURL) }
  }

  func selectFile(_ file: DiffChangedFile) {
    guard selectedFile != file else { return }
    selectedFile = file
    diffDocument = documentCache[file.id]
  }

  // MARK: - Private

  private func loadCommits(worktreeURL: URL, skip: Int) async {
    isLoadingCommits = true
    do {
      let output = try await GitClient().commitLog(
        at: worktreeURL,
        skip: skip,
        count: Self.pageSize
      )
      guard !Task.isCancelled else { return }
      let newCommits = GitLogCommit.parse(output)
      commits.append(contentsOf: newCommits)
      loadedCount = commits.count
      hasMoreCommits = newCommits.count >= Self.pageSize
    } catch {
      hasMoreCommits = false
    }
    isLoadingCommits = false

    if selectedCommit == nil, let first = commits.first {
      selectCommit(first)
    }
  }

  private func loadCommitDetail(commit: GitLogCommit, worktreeURL: URL) async {
    isLoadingDetail = true
    let output = await GitClient().commitDiffNameStatus(
      commit: commit.hash,
      at: worktreeURL
    )
    guard !Task.isCancelled else { return }
    let files = DiffChangedFile.parseNameStatus(output)
    commitFiles = files

    let documents = await Self.loadAllDocuments(
      files: files,
      commit: commit.hash,
      worktreeURL: worktreeURL
    )
    guard !Task.isCancelled else { return }
    documentCache = documents
    isLoadingDetail = false

    if let selectedFile, documents[selectedFile.id] != nil {
      diffDocument = documents[selectedFile.id]
    } else if let first = files.first {
      selectedFile = first
      diffDocument = documents[first.id]
    } else {
      selectedFile = nil
      diffDocument = nil
    }
  }

  private nonisolated static func loadAllDocuments(
    files: [DiffChangedFile],
    commit: String,
    worktreeURL: URL
  ) async -> [String: DiffDocument] {
    await withTaskGroup(of: (String, DiffDocument).self) { group in
      for file in files {
        group.addTask {
          let doc = await loadDocument(for: file, commit: commit, worktreeURL: worktreeURL)
          return (file.id, doc)
        }
      }
      var result: [String: DiffDocument] = [:]
      for await (id, doc) in group {
        result[id] = doc
      }
      return result
    }
  }

  private nonisolated static func loadDocument(
    for file: DiffChangedFile,
    commit: String,
    worktreeURL: URL
  ) async -> DiffDocument {
    let gitClient = GitClient()
    let oldContents: String
    let newContents: String

    switch file.status {
    case .added:
      oldContents = ""
      newContents = await gitClient.showFileAtCommit(
        file.displayPath, commit: commit, in: worktreeURL
      ) ?? ""
    case .deleted:
      oldContents = await gitClient.showFileAtCommit(
        file.oldPath ?? "", commit: "\(commit)~1", in: worktreeURL
      ) ?? ""
      newContents = ""
    case .renamed:
      oldContents = await gitClient.showFileAtCommit(
        file.oldPath ?? "", commit: "\(commit)~1", in: worktreeURL
      ) ?? ""
      newContents = await gitClient.showFileAtCommit(
        file.newPath ?? "", commit: commit, in: worktreeURL
      ) ?? ""
    default:
      let path = file.displayPath
      oldContents = await gitClient.showFileAtCommit(
        path, commit: "\(commit)~1", in: worktreeURL
      ) ?? ""
      newContents = await gitClient.showFileAtCommit(
        path, commit: commit, in: worktreeURL
      ) ?? ""
    }

    let diffFile = DiffFile(
      oldPath: file.oldPath,
      newPath: file.newPath,
      oldContents: oldContents,
      newContents: newContents,
    )
    return DiffDocument(files: [diffFile], title: file.displayName)
  }
}
