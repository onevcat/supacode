import Foundation
import Testing

@testable import supacode

@MainActor
struct WorktreeTerminalManagerTests {
  @Test func buffersEventsUntilStreamCreated() async {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.onSetupScriptConsumed?()

    let stream = manager.eventStream()
    let event = await nextEvent(stream) { event in
      if case .setupScriptConsumed = event {
        return true
      }
      return false
    }

    #expect(event == .setupScriptConsumed(worktreeID: worktree.id))
  }

  @Test func emitsEventsAfterStreamCreated() async {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    let stream = manager.eventStream()
    let eventTask = Task {
      await nextEvent(stream) { event in
        if case .setupScriptConsumed = event {
          return true
        }
        return false
      }
    }

    state.onSetupScriptConsumed?()

    let event = await eventTask.value
    #expect(event == .setupScriptConsumed(worktreeID: worktree.id))
  }

  @Test func fontSizeResetToBaselineEmitsNilOverride() async {
    let runtime = GhosttyRuntime()
    let baseline = runtime.defaultFontSize()
    let manager = WorktreeTerminalManager(runtime: runtime, preferredFontSize: baseline + 1)
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)
    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    state.onFontSizeChanged?(baseline)

    var event: TerminalClient.Event?
    while let next = await iterator.next() {
      if case .fontSizeChanged = next {
        event = next
        break
      }
    }

    #expect(event == .fontSizeChanged(nil))
  }

  @Test func duplicateFontSizeChangeIsDeduplicated() async {
    let runtime = GhosttyRuntime()
    let baseline = runtime.defaultFontSize()
    let firstSize = baseline + 2
    let secondSize = baseline + 3
    let manager = WorktreeTerminalManager(runtime: runtime)
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)
    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    state.onFontSizeChanged?(firstSize)
    state.onFontSizeChanged?(firstSize)
    state.onFontSizeChanged?(secondSize)

    var fontSizeEvents: [TerminalClient.Event] = []
    while let next = await iterator.next() {
      if case .fontSizeChanged = next {
        fontSizeEvents.append(next)
      }
      if fontSizeEvents.count == 2 {
        break
      }
    }

    #expect(fontSizeEvents == [.fontSizeChanged(firstSize), .fontSizeChanged(secondSize)])
  }

  @Test func explicitResetAcrossStatesEmitsNilOverride() async {
    let runtime = GhosttyRuntime()
    let baseline = runtime.defaultFontSize()
    let manager = WorktreeTerminalManager(runtime: runtime, preferredFontSize: baseline + 2)
    let worktreeA = Worktree(
      id: "/tmp/repo-a/wt-a",
      name: "wt-a",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo-a/wt-a"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo-a")
    )
    let worktreeB = Worktree(
      id: "/tmp/repo-b/wt-b",
      name: "wt-b",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo-b/wt-b"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo-b")
    )
    _ = manager.state(for: worktreeA)
    _ = manager.state(for: worktreeB)

    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    manager.resetFontSizeAcrossStates()

    var event: TerminalClient.Event?
    while let next = await iterator.next() {
      if case .fontSizeChanged = next {
        event = next
        break
      }
    }

    #expect(event == .fontSizeChanged(nil))
  }

  @Test func explicitResetWhenAlreadyDefaultDoesNotEmitEvent() async {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime(), preferredFontSize: nil)
    _ = manager.state(for: makeWorktree())
    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    manager.resetFontSizeAcrossStates()

    let first = await iterator.next()
    #expect(first == .notificationIndicatorChanged(count: 0))
  }

  @Test func cellSizeChangeSkipsFirstEventPerSurface() {
    let state = WorktreeTerminalState(runtime: GhosttyRuntime(), worktree: makeWorktree())
    var captured: [Float32?] = []
    let firstSurface = UUID()
    let secondSurface = UUID()

    state.onFontSizeChanged = { fontSize in
      captured.append(fontSize)
    }

    state.handleCellSizeChange(forSurfaceID: firstSurface, fontSize: 13)
    state.handleCellSizeChange(forSurfaceID: firstSurface, fontSize: 14)
    state.handleCellSizeChange(forSurfaceID: secondSurface, fontSize: 15)
    state.handleCellSizeChange(forSurfaceID: secondSurface, fontSize: 16)

    #expect(captured == [14, 16])
  }

  @Test func notificationIndicatorUsesCurrentCountOnStreamStart() async {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.notifications = [
      WorktreeTerminalNotification(
        surfaceId: UUID(),
        title: "Unread",
        body: "body",
        isRead: false
      ),
    ]
    state.onNotificationIndicatorChanged?()
    state.notifications = [
      WorktreeTerminalNotification(
        surfaceId: UUID(),
        title: "Read",
        body: "body",
        isRead: true
      ),
    ]

    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    let first = await iterator.next()
    state.onSetupScriptConsumed?()
    let second = await iterator.next()

    #expect(first == .notificationIndicatorChanged(count: 0))
    #expect(second == .setupScriptConsumed(worktreeID: worktree.id))
  }

  @Test func taskStatusReflectsAnyRunningTab() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    #expect(manager.taskStatus(for: worktree.id) == .idle)

    let tab1 = TerminalTabID()
    let tab2 = TerminalTabID()
    state.tabIsRunningById[tab1] = false
    state.tabIsRunningById[tab2] = false
    #expect(manager.taskStatus(for: worktree.id) == .idle)

    state.tabIsRunningById[tab2] = true
    #expect(manager.taskStatus(for: worktree.id) == .running)

    state.tabIsRunningById[tab1] = true
    #expect(manager.taskStatus(for: worktree.id) == .running)

    state.tabIsRunningById[tab2] = false
    #expect(manager.taskStatus(for: worktree.id) == .running)

    state.tabIsRunningById[tab1] = false
    #expect(manager.taskStatus(for: worktree.id) == .idle)
  }

  @Test func hasUnseenNotificationsReflectsUnreadEntries() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.notifications = [
      makeNotification(isRead: true),
      makeNotification(isRead: true),
    ]

    #expect(manager.hasUnseenNotifications(for: worktree.id) == false)

    state.notifications.append(makeNotification(isRead: false))

    #expect(manager.hasUnseenNotifications(for: worktree.id) == true)
  }

  @Test func markAllNotificationsReadEmitsUpdatedIndicatorCount() async {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.notifications = [
      makeNotification(isRead: false),
      makeNotification(isRead: true),
    ]

    let stream = manager.eventStream()
    var iterator = stream.makeAsyncIterator()

    let first = await iterator.next()
    state.markAllNotificationsRead()
    let second = await iterator.next()

    #expect(first == .notificationIndicatorChanged(count: 1))
    #expect(second == .notificationIndicatorChanged(count: 0))
    #expect(state.notifications.map(\.isRead) == [true, true])
  }

  @Test func markNotificationsReadOnlyAffectsMatchingSurface() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)
    let surfaceA = UUID()
    let surfaceB = UUID()

    state.notifications = [
      makeNotification(surfaceId: surfaceA, isRead: false),
      makeNotification(surfaceId: surfaceB, isRead: false),
      makeNotification(surfaceId: surfaceB, isRead: true),
    ]

    state.markNotificationsRead(forSurfaceID: surfaceB)

    let aNotifications = state.notifications.filter { $0.surfaceId == surfaceA }
    let bNotifications = state.notifications.filter { $0.surfaceId == surfaceB }

    #expect(aNotifications.map(\.isRead) == [false])
    #expect(bNotifications.map(\.isRead) == [true, true])
    #expect(manager.hasUnseenNotifications(for: worktree.id) == true)

    state.markNotificationsRead(forSurfaceID: surfaceA)

    #expect(manager.hasUnseenNotifications(for: worktree.id) == false)
  }

  @Test func setNotificationsDisabledMarksAllRead() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.notifications = [
      makeNotification(isRead: false),
      makeNotification(isRead: false),
    ]

    state.setNotificationsEnabled(false)

    #expect(state.notifications.map(\.isRead) == [true, true])
    #expect(manager.hasUnseenNotifications(for: worktree.id) == false)
  }

  @Test func dismissAllNotificationsClearsState() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.notifications = [
      makeNotification(isRead: false),
      makeNotification(isRead: true),
    ]

    state.dismissAllNotifications()

    #expect(state.notifications.isEmpty)
    #expect(manager.hasUnseenNotifications(for: worktree.id) == false)
  }

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
  }

  private func nextEvent(
    _ stream: AsyncStream<TerminalClient.Event>,
    matching predicate: (TerminalClient.Event) -> Bool
  ) async -> TerminalClient.Event? {
    for await event in stream where predicate(event) {
      return event
    }
    return nil
  }

  private func makeNotification(
    surfaceId: UUID = UUID(),
    isRead: Bool
  ) -> WorktreeTerminalNotification {
    WorktreeTerminalNotification(
      surfaceId: surfaceId,
      title: "Title",
      body: "Body",
      isRead: isRead
    )
  }
}
