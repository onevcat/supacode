import Foundation
import Testing

@testable import supacode

@MainActor
struct WorktreeInfoWatcherManagerTests {
  @Test func defersLineChangesUntilSchedule() async throws {
    let (worktree, tempRoot, _) = try makeTempWorktree()
    let manager = WorktreeInfoWatcherManager(
      focusedInterval: .milliseconds(50),
      unfocusedInterval: .milliseconds(50)
    )
    let (collector, task) = startCollecting(manager.eventStream())

    manager.handleCommand(.setPullRequestTrackingEnabled(false))
    manager.handleCommand(.setWorktrees([worktree]))
    manager.handleCommand(.setSelectedWorktreeID(worktree.id))

    try? await Task.sleep(for: .milliseconds(20))
    let earlyHasFilesChanged = await collector.hasFilesChanged(worktreeID: worktree.id)
    #expect(earlyHasFilesChanged == false)

    #expect(
      await waitForFilesChangedCount(
        collector,
        worktreeID: worktree.id,
        count: 1,
        timeout: .seconds(1)
      )
    )

    manager.handleCommand(.stop)
    await task.value
    try FileManager.default.removeItem(at: tempRoot)
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

}

private func makeTempWorktree() throws -> (Worktree, URL, URL) {
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
  return (worktree, tempRoot, headURL)
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
