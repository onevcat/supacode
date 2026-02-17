import Foundation
import Testing

@testable import supacode

@MainActor
struct WorktreeInfoWatcherManagerTests {
  @Test func emitsLineChangesImmediatelyOnInitialWorktreeLoad() async throws {
    let tempWorktree = try makeTempWorktree()
    let manager = WorktreeInfoWatcherManager(
      focusedInterval: .seconds(3_600),
      unfocusedInterval: .seconds(3_600)
    )
    let (collector, task) = startCollecting(manager.eventStream())

    manager.handleCommand(.setPullRequestTrackingEnabled(false))
    manager.handleCommand(.setWorktrees([tempWorktree.worktree]))

    #expect(
      await waitForFilesChangedCount(
        collector,
        worktreeID: tempWorktree.worktree.id,
        count: 1,
        timeout: .milliseconds(300)
      )
    )

    manager.handleCommand(.stop)
    await task.value
    try FileManager.default.removeItem(at: tempWorktree.tempRoot)
  }

  @Test func defersLineChangesForWorktreesAddedAfterInitialLoad() async throws {
    let tempRepository = try makeTempRepository(worktreeNames: ["sparrow", "swift"])
    let firstWorktree = try #require(tempRepository.worktrees.first)
    let secondWorktree = try #require(tempRepository.worktrees.dropFirst().first)
    let manager = WorktreeInfoWatcherManager(
      focusedInterval: .milliseconds(80),
      unfocusedInterval: .milliseconds(80)
    )
    let (collector, task) = startCollecting(manager.eventStream())

    manager.handleCommand(.setPullRequestTrackingEnabled(false))
    manager.handleCommand(.setWorktrees([firstWorktree]))

    #expect(
      await waitForFilesChangedCount(
        collector,
        worktreeID: firstWorktree.id,
        count: 1,
        timeout: .milliseconds(300)
      )
    )

    manager.handleCommand(.setWorktrees([firstWorktree, secondWorktree]))

    try? await Task.sleep(for: .milliseconds(20))
    #expect(await collector.hasFilesChanged(worktreeID: secondWorktree.id) == false)

    #expect(
      await waitForFilesChangedCount(
        collector,
        worktreeID: secondWorktree.id,
        count: 1,
        timeout: .seconds(1)
      )
    )

    manager.handleCommand(.stop)
    await task.value
    try FileManager.default.removeItem(at: tempRepository.tempRoot)
  }

  @Test func selectionRefreshUsesCooldownWithinRepository() async throws {
    let tempRepository = try makeTempRepository(worktreeNames: ["sparrow", "swift"])
    let manager = WorktreeInfoWatcherManager(
      focusedInterval: .seconds(3_600),
      unfocusedInterval: .seconds(3_600),
      pullRequestSelectionRefreshCooldown: .milliseconds(200)
    )
    let (collector, task) = startCollecting(manager.eventStream())

    manager.handleCommand(.setWorktrees(tempRepository.worktrees))
    #expect(
      await waitForPullRequestRefreshCount(
        collector,
        repositoryRootURL: tempRepository.tempRoot,
        count: 1,
        timeout: .seconds(2)
      )
    )
    let baselineCount = await collector.pullRequestRefreshCount(repositoryRootURL: tempRepository.tempRoot)
    let firstWorktree = try #require(tempRepository.worktrees.first)
    let secondWorktree = try #require(tempRepository.worktrees.dropFirst().first)

    manager.handleCommand(.setSelectedWorktreeID(firstWorktree.id))
    try? await Task.sleep(for: .milliseconds(20))
    manager.handleCommand(.setSelectedWorktreeID(secondWorktree.id))
    #expect(
      await waitForPullRequestRefreshCount(
        collector,
        repositoryRootURL: tempRepository.tempRoot,
        count: baselineCount + 1,
        timeout: .seconds(2)
      )
    )

    try? await Task.sleep(for: .milliseconds(80))
    #expect(
      await collector.pullRequestRefreshCount(repositoryRootURL: tempRepository.tempRoot) == baselineCount + 1
    )

    try? await Task.sleep(for: .milliseconds(220))
    manager.handleCommand(.setSelectedWorktreeID(firstWorktree.id))
    #expect(
      await waitForPullRequestRefreshCount(
        collector,
        repositoryRootURL: tempRepository.tempRoot,
        count: baselineCount + 2,
        timeout: .seconds(2)
      )
    )

    manager.handleCommand(.stop)
    await task.value
    try FileManager.default.removeItem(at: tempRepository.tempRoot)
  }
}

actor EventCollector {
  private var events: [WorktreeInfoWatcherClient.Event] = []

  func append(_ event: WorktreeInfoWatcherClient.Event) {
    events.append(event)
  }

  func filesChangedCount(worktreeID: Worktree.ID) -> Int {
    events.reduce(into: 0) { result, event in
      if case .filesChanged(let id) = event, id == worktreeID {
        result += 1
      }
    }
  }

  func hasFilesChanged(worktreeID: Worktree.ID) -> Bool {
    filesChangedCount(worktreeID: worktreeID) > 0
  }

  func pullRequestRefreshCount(repositoryRootURL: URL) -> Int {
    events.reduce(into: 0) { result, event in
      if case .repositoryPullRequestRefresh(let rootURL, _) = event, rootURL == repositoryRootURL {
        result += 1
      }
    }
  }
}

private struct TempWorktree {
  let worktree: Worktree
  let tempRoot: URL
  let headURL: URL
}

private struct TempRepository {
  let worktrees: [Worktree]
  let tempRoot: URL
}

private func makeTempWorktree() throws -> TempWorktree {
  let fileManager = FileManager.default
  let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
  let worktreeDirectory = tempRoot.appending(path: "wt")
  let gitDirectory = worktreeDirectory.appending(path: ".git")
  try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
  let headURL = gitDirectory.appending(path: "HEAD")
  try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)
  let worktree = Worktree(
    id: worktreeDirectory.path(percentEncoded: false),
    name: "eagle",
    detail: "detail",
    workingDirectory: worktreeDirectory,
    repositoryRootURL: tempRoot
  )
  return TempWorktree(worktree: worktree, tempRoot: tempRoot, headURL: headURL)
}

private func makeTempRepository(worktreeNames: [String]) throws -> TempRepository {
  let fileManager = FileManager.default
  let tempRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
  var worktrees: [Worktree] = []
  for name in worktreeNames {
    let worktreeDirectory = tempRoot.appending(path: name)
    let gitDirectory = worktreeDirectory.appending(path: ".git")
    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let headURL = gitDirectory.appending(path: "HEAD")
    try "ref: refs/heads/\(name)\n".write(to: headURL, atomically: true, encoding: .utf8)
    let worktree = Worktree(
      id: worktreeDirectory.path(percentEncoded: false),
      name: name,
      detail: "detail",
      workingDirectory: worktreeDirectory,
      repositoryRootURL: tempRoot
    )
    worktrees.append(worktree)
  }
  return TempRepository(worktrees: worktrees, tempRoot: tempRoot)
}

private func startCollecting(
  _ stream: AsyncStream<WorktreeInfoWatcherClient.Event>
) -> (EventCollector, Task<Void, Never>) {
  let collector = EventCollector()
  let task = Task {
    for await event in stream {
      if Task.isCancelled {
        break
      }
      await collector.append(event)
    }
  }
  return (collector, task)
}

private func waitForFilesChangedCount(
  _ collector: EventCollector,
  worktreeID: Worktree.ID,
  count: Int,
  timeout: Duration
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await collector.filesChangedCount(worktreeID: worktreeID) >= count {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return false
}

private func waitForPullRequestRefreshCount(
  _ collector: EventCollector,
  repositoryRootURL: URL,
  count: Int,
  timeout: Duration
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await collector.pullRequestRefreshCount(repositoryRootURL: repositoryRootURL) >= count {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return false
}
