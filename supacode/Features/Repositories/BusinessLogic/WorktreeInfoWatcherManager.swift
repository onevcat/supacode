import Dispatch
import Foundation
import Darwin

@MainActor
final class WorktreeInfoWatcherManager {
  private struct HeadWatcher {
    let headURL: URL
    let source: DispatchSourceFileSystemObject
  }

  private struct RefreshTask {
    let interval: Duration
    let task: Task<Void, Never>
  }

  private enum RefreshTiming {
    static let focused = Duration.seconds(30)
    static let unfocused = Duration.seconds(300)
  }

  private var worktrees: [Worktree.ID: Worktree] = [:]
  private var headWatchers: [Worktree.ID: HeadWatcher] = [:]
  private var branchDebounceTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var filesDebounceTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var restartTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var pullRequestTasks: [Worktree.ID: RefreshTask] = [:]
  private var lineChangeTasks: [Worktree.ID: RefreshTask] = [:]
  private var selectedWorktreeID: Worktree.ID?
  private var eventContinuation: AsyncStream<WorktreeInfoWatcherClient.Event>.Continuation?

  func handleCommand(_ command: WorktreeInfoWatcherClient.Command) {
    switch command {
    case .setWorktrees(let worktrees):
      setWorktrees(worktrees)
    case .setSelectedWorktreeID(let worktreeID):
      setSelectedWorktreeID(worktreeID)
    case .stop:
      stopAll()
    }
  }

  func eventStream() -> AsyncStream<WorktreeInfoWatcherClient.Event> {
    eventContinuation?.finish()
    let (stream, continuation) = AsyncStream.makeStream(of: WorktreeInfoWatcherClient.Event.self)
    eventContinuation = continuation
    return stream
  }

  private func setWorktrees(_ worktrees: [Worktree]) {
    let worktreesByID = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
    let desiredIDs = Set(worktreesByID.keys)
    let currentIDs = Set(self.worktrees.keys)
    let removedIDs = currentIDs.subtracting(desiredIDs)
    for id in removedIDs {
      stopWatcher(for: id)
    }
    self.worktrees = worktreesByID
    for worktree in worktrees {
      configureWatcher(for: worktree)
      updatePullRequestSchedule(worktreeID: worktree.id, immediate: true)
      updateLineChangeSchedule(worktreeID: worktree.id, immediate: true)
    }
  }

  private func setSelectedWorktreeID(_ worktreeID: Worktree.ID?) {
    guard selectedWorktreeID != worktreeID else {
      return
    }
    let previousWorktreeID = selectedWorktreeID
    selectedWorktreeID = worktreeID
    if let previousWorktreeID {
      updatePullRequestSchedule(worktreeID: previousWorktreeID, immediate: false)
      updateLineChangeSchedule(worktreeID: previousWorktreeID, immediate: false)
    }
    if let worktreeID {
      updatePullRequestSchedule(worktreeID: worktreeID, immediate: true)
      updateLineChangeSchedule(worktreeID: worktreeID, immediate: true)
    }
  }

  private func configureWatcher(for worktree: Worktree) {
    guard let headURL = GitWorktreeHeadResolver.headURL(
      for: worktree.workingDirectory,
      fileManager: .default
    ) else {
      stopWatcher(for: worktree.id)
      return
    }
    if let existing = headWatchers[worktree.id], existing.headURL == headURL {
      return
    }
    stopWatcher(for: worktree.id)
    startWatcher(worktreeID: worktree.id, headURL: headURL)
  }

  private func startWatcher(worktreeID: Worktree.ID, headURL: URL) {
    let path = headURL.path(percentEncoded: false)
    let fileDescriptor = open(path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      return
    }
    let queue = DispatchQueue(label: "worktree-info-watcher.\(worktreeID)")
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .attrib],
      queue: queue
    )
    source.setEventHandler { [weak self, weak source] in
      guard let source else { return }
      let event = source.data
      Task { @MainActor in
        self?.handleEvent(worktreeID: worktreeID, event: event)
      }
    }
    source.setCancelHandler {
      close(fileDescriptor)
    }
    source.resume()
    headWatchers[worktreeID] = HeadWatcher(headURL: headURL, source: source)
  }

  private func handleEvent(
    worktreeID: Worktree.ID,
    event: DispatchSource.FileSystemEvent
  ) {
    if event.contains(.delete) || event.contains(.rename) {
      stopHeadWatcher(for: worktreeID)
      scheduleRestart(worktreeID: worktreeID)
      scheduleBranchChanged(worktreeID: worktreeID)
      return
    }
    scheduleBranchChanged(worktreeID: worktreeID)
    scheduleFilesChanged(worktreeID: worktreeID)
  }

  private func scheduleBranchChanged(worktreeID: Worktree.ID) {
    branchDebounceTasks[worktreeID]?.cancel()
    let task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      await MainActor.run {
        self?.emit(.branchChanged(worktreeID: worktreeID))
      }
    }
    branchDebounceTasks[worktreeID] = task
  }

  private func scheduleFilesChanged(worktreeID: Worktree.ID) {
    filesDebounceTasks[worktreeID]?.cancel()
    let task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      await MainActor.run {
        self?.emit(.filesChanged(worktreeID: worktreeID))
      }
    }
    filesDebounceTasks[worktreeID] = task
  }

  private func scheduleRestart(worktreeID: Worktree.ID) {
    restartTasks[worktreeID]?.cancel()
    let task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      await MainActor.run {
        self?.restartWatcher(worktreeID: worktreeID)
      }
    }
    restartTasks[worktreeID] = task
  }

  private func restartWatcher(worktreeID: Worktree.ID) {
    guard headWatchers[worktreeID] == nil else {
      return
    }
    guard let worktree = worktrees[worktreeID] else {
      return
    }
    configureWatcher(for: worktree)
  }

  private func stopHeadWatcher(for worktreeID: Worktree.ID) {
    if let watcher = headWatchers.removeValue(forKey: worktreeID) {
      watcher.source.cancel()
    }
  }

  private func stopWatcher(for worktreeID: Worktree.ID) {
    stopHeadWatcher(for: worktreeID)
    branchDebounceTasks.removeValue(forKey: worktreeID)?.cancel()
    filesDebounceTasks.removeValue(forKey: worktreeID)?.cancel()
    restartTasks.removeValue(forKey: worktreeID)?.cancel()
    pullRequestTasks.removeValue(forKey: worktreeID)?.task.cancel()
    lineChangeTasks.removeValue(forKey: worktreeID)?.task.cancel()
  }

  private func stopAll() {
    for (id, watcher) in headWatchers {
      watcher.source.cancel()
      branchDebounceTasks.removeValue(forKey: id)?.cancel()
      filesDebounceTasks.removeValue(forKey: id)?.cancel()
      restartTasks.removeValue(forKey: id)?.cancel()
      pullRequestTasks.removeValue(forKey: id)?.task.cancel()
      lineChangeTasks.removeValue(forKey: id)?.task.cancel()
    }
    headWatchers.removeAll()
    worktrees.removeAll()
    selectedWorktreeID = nil
    eventContinuation?.finish()
  }

  private func updatePullRequestSchedule(worktreeID: Worktree.ID, immediate: Bool) {
    guard worktrees[worktreeID] != nil else {
      return
    }
    let interval = worktreeID == selectedWorktreeID ? RefreshTiming.focused : RefreshTiming.unfocused
    updateRepeatingTask(
      worktreeID: worktreeID,
      interval: interval,
      immediate: immediate,
      tasks: &pullRequestTasks
    ) { .pullRequestRefresh(worktreeID: $0) }
  }

  private func updateLineChangeSchedule(worktreeID: Worktree.ID, immediate: Bool) {
    guard worktrees[worktreeID] != nil else {
      return
    }
    let interval = worktreeID == selectedWorktreeID ? RefreshTiming.focused : RefreshTiming.unfocused
    updateRepeatingTask(
      worktreeID: worktreeID,
      interval: interval,
      immediate: immediate,
      tasks: &lineChangeTasks
    ) { .filesChanged(worktreeID: $0) }
  }

  private func updateRepeatingTask(
    worktreeID: Worktree.ID,
    interval: Duration,
    immediate: Bool,
    tasks: inout [Worktree.ID: RefreshTask],
    makeEvent: @escaping (Worktree.ID) -> WorktreeInfoWatcherClient.Event
  ) {
    if let existing = tasks[worktreeID], existing.interval == interval {
      if immediate {
        emit(makeEvent(worktreeID))
      }
      return
    }
    tasks[worktreeID]?.task.cancel()
    if immediate {
      emit(makeEvent(worktreeID))
    }
    let task = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        await MainActor.run {
          self?.emit(makeEvent(worktreeID))
        }
      }
    }
    tasks[worktreeID] = RefreshTask(interval: interval, task: task)
  }

  private func emit(_ event: WorktreeInfoWatcherClient.Event) {
    eventContinuation?.yield(event)
  }
}
