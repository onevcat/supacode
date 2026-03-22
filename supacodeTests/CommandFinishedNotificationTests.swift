import Foundation
import Testing

@testable import supacode

@MainActor
struct CommandFinishedNotificationTests {
  private let surfaceId = UUID()

  // MARK: - Notification Generation

  @Test func generatesNotificationWhenThresholdExceeded() {
    let state = makeState()
    state.handleCommandFinished(exitCode: 0, durationNs: 15_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
    #expect(state.notifications.first?.title == "Command finished")
    #expect(state.notifications.first?.body == "Completed in 15s")
    #expect(state.notifications.first?.surfaceId == surfaceId)
  }

  @Test func doesNotGenerateNotificationUnderThreshold() {
    let state = makeState()
    state.handleCommandFinished(exitCode: 0, durationNs: 5_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)
  }

  @Test func doesNotGenerateNotificationAtExactThreshold() {
    let state = makeState(threshold: 10)
    state.handleCommandFinished(exitCode: 0, durationNs: 10_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
  }

  // MARK: - Exit Code Filtering

  @Test func doesNotGenerateNotificationForSIGINT() {
    let state = makeState()
    state.handleCommandFinished(exitCode: 130, durationNs: 60_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)
  }

  @Test func doesNotGenerateNotificationForSIGTERM() {
    let state = makeState()
    state.handleCommandFinished(exitCode: 143, durationNs: 60_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)
  }

  @Test func generatesFailureNotificationForNonZeroExitCode() {
    let state = makeState()
    state.handleCommandFinished(exitCode: 1, durationNs: 30_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
    #expect(state.notifications.first?.title == "Command failed")
    #expect(state.notifications.first?.body == "Failed (exit code 1) after 30s")
  }

  @Test func generatesNotificationForNilExitCode() {
    let state = makeState()
    state.handleCommandFinished(exitCode: nil, durationNs: 20_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
    #expect(state.notifications.first?.title == "Command finished")
    #expect(state.notifications.first?.body == "Completed in 20s")
  }

  // MARK: - Feature Toggle

  @Test func doesNotGenerateNotificationWhenDisabled() {
    let state = makeState()
    state.setCommandFinishedNotification(enabled: false, threshold: 10)
    state.handleCommandFinished(exitCode: 0, durationNs: 60_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)
  }

  @Test func respectsUpdatedThreshold() {
    let state = makeState()
    state.setCommandFinishedNotification(enabled: true, threshold: 30)
    state.handleCommandFinished(exitCode: 0, durationNs: 20_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)

    state.handleCommandFinished(exitCode: 0, durationNs: 31_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
  }

  // MARK: - Duration Formatting

  @Test func formatDurationSeconds() {
    #expect(WorktreeTerminalState.formatDuration(5) == "5s")
    #expect(WorktreeTerminalState.formatDuration(59) == "59s")
  }

  @Test func formatDurationMinutes() {
    #expect(WorktreeTerminalState.formatDuration(60) == "1m")
    #expect(WorktreeTerminalState.formatDuration(90) == "1m 30s")
    #expect(WorktreeTerminalState.formatDuration(3599) == "59m 59s")
  }

  @Test func formatDurationHours() {
    #expect(WorktreeTerminalState.formatDuration(3600) == "1h")
    #expect(WorktreeTerminalState.formatDuration(3660) == "1h 1m")
    #expect(WorktreeTerminalState.formatDuration(7200) == "2h")
  }

  // MARK: - Manager Propagation

  @Test func managerPropagatesSettingsToExistingStates() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    manager.setCommandFinishedNotification(enabled: true, threshold: 30)
    state.handleCommandFinished(exitCode: 0, durationNs: 20_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.isEmpty)

    state.handleCommandFinished(exitCode: 0, durationNs: 31_000_000_000, surfaceId: surfaceId)

    #expect(state.notifications.count == 1)
  }

  @Test func managerPropagatesSettingsToNewStates() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    manager.setCommandFinishedNotification(enabled: true, threshold: 60)

    let worktree = makeWorktree()
    let state = manager.state(for: worktree)

    state.handleCommandFinished(exitCode: 0, durationNs: 30_000_000_000, surfaceId: surfaceId)
    #expect(state.notifications.isEmpty)

    state.handleCommandFinished(exitCode: 0, durationNs: 61_000_000_000, surfaceId: surfaceId)
    #expect(state.notifications.count == 1)
  }

  // MARK: - Helpers

  private func makeState(threshold: Int = 10) -> WorktreeTerminalState {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let worktree = makeWorktree()
    let state = manager.state(for: worktree)
    state.setCommandFinishedNotification(enabled: true, threshold: threshold)
    return state
  }

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-\(UUID().uuidString)",
      name: "wt-test",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-test"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
    )
  }
}
