import Darwin
import Dispatch
import Foundation

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

  private struct RepeatingTaskRequest {
    let worktreeID: Worktree.ID
    let interval: Duration
    let immediate: Bool
    let forceReschedule: Bool
    let makeEvent: (Worktree.ID) -> WorktreeInfoWatcherClient.Event
  }

  private struct RefreshTiming: Equatable {
    let focused: Duration
    let unfocused: Duration
  }

  private let filesChangedDebounceInterval: Duration
  private let pullRequestSelectionRefreshCooldown: Duration
  private let refreshTiming: RefreshTiming
  private let clock: ContinuousClock
  private var worktrees: [Worktree.ID: Worktree] = [:]
  private var headWatchers: [Worktree.ID: HeadWatcher] = [:]
  private var branchDebounceTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var filesDebounceTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var restartTasks: [Worktree.ID: Task<Void, Never>] = [:]
  private var pullRequestTasks: [URL: RefreshTask] = [:]
  private var lineChangeTasks: [Worktree.ID: RefreshTask] = [:]
  private var deferredLineChangeIDs: Set<Worktree.ID> = []
  private var selectedWorktreeID: Worktree.ID?
  private var pullRequestTrackingEnabled = true
  private var lastImmediatePullRequestRefreshByRepo: [URL: ContinuousClock.Instant] = [:]
  private var eventContinuation: AsyncStream<WorktreeInfoWatcherClient.Event>.Continuation?

  init(
    focusedInterval: Duration = .seconds(30),
    unfocusedInterval: Duration = .seconds(60),
    filesChangedDebounceInterval: Duration = .seconds(5),
    pullRequestSelectionRefreshCooldown: Duration = .seconds(7),
    clock: ContinuousClock = ContinuousClock()
  ) {
    refreshTiming = RefreshTiming(focused: focusedInterval, unfocused: unfocusedInterval)
    self.filesChangedDebounceInterval = filesChangedDebounceInterval
    self.pullRequestSelectionRefreshCooldown = pullRequestSelectionRefreshCooldown
    self.clock = clock
  }

  func handleCommand(_ command: WorktreeInfoWatcherClient.Command) {
    switch command {
    case .setWorktrees(let worktrees):
      setWorktrees(worktrees)
    case .setSelectedWorktreeID(let worktreeID):
      setSelectedWorktreeID(worktreeID)
    case .setPullRequestTrackingEnabled(let isEnabled):
      setPullRequestTrackingEnabled(isEnabled)
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
    if !removedIDs.isEmpty {
      deferredLineChangeIDs.subtract(removedIDs)
    }
    let newIDs = desiredIDs.subtracting(currentIDs)
    if !newIDs.isEmpty {
      deferredLineChangeIDs.formUnion(newIDs)
    }
    self.worktrees = worktreesByID
    for worktree in worktrees {
      configureWatcher(for: worktree)
      updateLineChangeSchedule(
        worktreeID: worktree.id,
        immediate: !deferredLineChangeIDs.contains(worktree.id)
      )
    }
    let repositoryRoots = Set(worktrees.map(\.repositoryRootURL))
    for repositoryRootURL in repositoryRoots {
      updatePullRequestSchedule(repositoryRootURL: repositoryRootURL, immediate: true)
    }
    let obsoleteRepositories = pullRequestTasks.keys.filter { !repositoryRoots.contains($0) }
    for repositoryRootURL in obsoleteRepositories {
      pullRequestTasks.removeValue(forKey: repositoryRootURL)?.task.cancel()
    }
    lastImmediatePullRequestRefreshByRepo = lastImmediatePullRequestRefreshByRepo.filter {
      repositoryRoots.contains($0.key)
    }
  }

  private func setSelectedWorktreeID(_ worktreeID: Worktree.ID?) {
    guard selectedWorktreeID != worktreeID else {
      return
    }
    let previousWorktreeID = selectedWorktreeID
    let previousRepository = previousWorktreeID.flatMap { worktrees[$0]?.repositoryRootURL }
    selectedWorktreeID = worktreeID
    let nextRepository = worktreeID.flatMap { worktrees[$0]?.repositoryRootURL }
    if let previousWorktreeID {
      updateLineChangeSchedule(worktreeID: previousWorktreeID, immediate: false)
    }
    if let worktreeID {
      updateLineChangeSchedule(worktreeID: worktreeID, immediate: true)
    }
    if let previousRepository, previousRepository == nextRepository {
      updatePullRequestSchedule(
        repositoryRootURL: previousRepository,
        immediate: shouldImmediatelyRefreshPullRequests(repositoryRootURL: previousRepository)
      )
      return
    }
    if let previousRepository {
      updatePullRequestSchedule(repositoryRootURL: previousRepository, immediate: false)
    }
    if let nextRepository {
      updatePullRequestSchedule(
        repositoryRootURL: nextRepository,
        immediate: shouldImmediatelyRefreshPullRequests(repositoryRootURL: nextRepository)
      )
    }
  }

  private func configureWatcher(for worktree: Worktree) {
    guard
      let headURL = GitWorktreeHeadResolver.headURL(
        for: worktree.workingDirectory,
        fileManager: .default
      )
    else {
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
    let debounceInterval = filesChangedDebounceInterval
    let task = Task { [weak self] in
      try? await Task.sleep(for: debounceInterval)
      await MainActor.run {
        guard let self else { return }
        self.emit(.filesChanged(worktreeID: worktreeID))
        if !self.deferredLineChangeIDs.contains(worktreeID) {
          self.updateLineChangeSchedule(
            worktreeID: worktreeID,
            immediate: false,
            forceReschedule: true
          )
        }
      }
    }
    filesDebounceTasks[worktreeID] = task
  }

  private func scheduleRestart(worktreeID: Worktree.ID) {
    restartTasks[worktreeID]?.cancel()
    let task = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
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
    scheduleBranchChanged(worktreeID: worktreeID)
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
    lineChangeTasks.removeValue(forKey: worktreeID)?.task.cancel()
  }

  private func stopAll() {
    for watcher in headWatchers.values {
      watcher.source.cancel()
    }
    for task in branchDebounceTasks.values {
      task.cancel()
    }
    for task in filesDebounceTasks.values {
      task.cancel()
    }
    for task in restartTasks.values {
      task.cancel()
    }
    for task in pullRequestTasks.values {
      task.task.cancel()
    }
    for task in lineChangeTasks.values {
      task.task.cancel()
    }
    headWatchers.removeAll()
    branchDebounceTasks.removeAll()
    filesDebounceTasks.removeAll()
    restartTasks.removeAll()
    pullRequestTasks.removeAll()
    lineChangeTasks.removeAll()
    deferredLineChangeIDs.removeAll()
    lastImmediatePullRequestRefreshByRepo.removeAll()
    worktrees.removeAll()
    selectedWorktreeID = nil
    pullRequestTrackingEnabled = true
    eventContinuation?.finish()
  }

  private func setPullRequestTrackingEnabled(_ enabled: Bool) {
    guard pullRequestTrackingEnabled != enabled else {
      return
    }
    pullRequestTrackingEnabled = enabled
    if enabled {
      let repositoryRoots = Set(worktrees.values.map(\.repositoryRootURL))
      for repositoryRootURL in repositoryRoots {
        updatePullRequestSchedule(repositoryRootURL: repositoryRootURL, immediate: true)
      }
      return
    }
    for task in pullRequestTasks.values {
      task.task.cancel()
    }
    pullRequestTasks.removeAll()
    lastImmediatePullRequestRefreshByRepo.removeAll()
  }

  private func updatePullRequestSchedule(repositoryRootURL: URL, immediate: Bool) {
    guard pullRequestTrackingEnabled else {
      pullRequestTasks.removeValue(forKey: repositoryRootURL)?.task.cancel()
      return
    }
    let worktreeIDs = repositoryWorktreeIDs(for: repositoryRootURL)
    guard !worktreeIDs.isEmpty else {
      pullRequestTasks.removeValue(forKey: repositoryRootURL)?.task.cancel()
      return
    }
    let isFocused = selectedWorktreeID.map { worktreeIDs.contains($0) } ?? false
    let interval = isFocused ? refreshTiming.focused : refreshTiming.unfocused
    if let existing = pullRequestTasks[repositoryRootURL], existing.interval == interval, !immediate {
      return
    }
    pullRequestTasks[repositoryRootURL]?.task.cancel()
    if immediate {
      emitPullRequestRefresh(repositoryRootURL: repositoryRootURL)
    }
    let task = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }
        guard !Task.isCancelled else {
          break
        }
        await MainActor.run {
          self?.emitPullRequestRefresh(repositoryRootURL: repositoryRootURL)
        }
      }
    }
    pullRequestTasks[repositoryRootURL] = RefreshTask(interval: interval, task: task)
  }

  private func repositoryWorktreeIDs(for repositoryRootURL: URL) -> [Worktree.ID] {
    worktrees
      .values
      .filter { $0.repositoryRootURL == repositoryRootURL }
      .map(\.id)
      .sorted()
  }

  private func emitPullRequestRefresh(repositoryRootURL: URL) {
    guard pullRequestTrackingEnabled else {
      return
    }
    let worktreeIDs = repositoryWorktreeIDs(for: repositoryRootURL)
    guard !worktreeIDs.isEmpty else {
      return
    }
    emit(.repositoryPullRequestRefresh(repositoryRootURL: repositoryRootURL, worktreeIDs: worktreeIDs))
  }

  private func updateLineChangeSchedule(
    worktreeID: Worktree.ID,
    immediate: Bool,
    forceReschedule: Bool = false
  ) {
    guard worktrees[worktreeID] != nil else {
      return
    }
    let interval = worktreeID == selectedWorktreeID ? refreshTiming.focused : refreshTiming.unfocused
    let shouldEmit = immediate && !deferredLineChangeIDs.contains(worktreeID)
    let request = RepeatingTaskRequest(
      worktreeID: worktreeID,
      interval: interval,
      immediate: shouldEmit,
      forceReschedule: forceReschedule,
      makeEvent: { [weak self] worktreeID in
        self?.deferredLineChangeIDs.remove(worktreeID)
        return .filesChanged(worktreeID: worktreeID)
      }
    )
    updateRepeatingTask(request, tasks: &lineChangeTasks)
  }

  private func updateRepeatingTask(
    _ request: RepeatingTaskRequest,
    tasks: inout [Worktree.ID: RefreshTask]
  ) {
    let worktreeID = request.worktreeID
    if let existing = tasks[worktreeID], existing.interval == request.interval, !request.forceReschedule {
      if request.immediate {
        emit(request.makeEvent(worktreeID))
      }
      return
    }
    tasks[worktreeID]?.task.cancel()
    if request.immediate {
      emit(request.makeEvent(worktreeID))
    }
    let task = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: request.interval)
        } catch {
          break
        }
        guard !Task.isCancelled else {
          break
        }
        await MainActor.run {
          self?.emit(request.makeEvent(worktreeID))
        }
      }
    }
    tasks[worktreeID] = RefreshTask(interval: request.interval, task: task)
  }

  private func emit(_ event: WorktreeInfoWatcherClient.Event) {
    if case .filesChanged(let worktreeID) = event,
      deferredLineChangeIDs.contains(worktreeID)
    {
      return
    }
    eventContinuation?.yield(event)
  }

  private func shouldImmediatelyRefreshPullRequests(repositoryRootURL: URL) -> Bool {
    let now = clock.now
    guard let lastRefresh = lastImmediatePullRequestRefreshByRepo[repositoryRootURL] else {
      lastImmediatePullRequestRefreshByRepo[repositoryRootURL] = now
      return true
    }
    guard lastRefresh.duration(to: now) >= pullRequestSelectionRefreshCooldown else {
      return false
    }
    lastImmediatePullRequestRefreshByRepo[repositoryRootURL] = now
    return true
  }
}
