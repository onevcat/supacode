import Foundation
import Testing

@testable import supacode

nonisolated final class RemoteExecutionCallRecorder: @unchecked Sendable {
  struct Snapshot {
    let executableURL: URL?
    let arguments: [String]
    let timeoutSeconds: Int
  }

  private let lock = NSLock()
  private var executableURLValue: URL?
  private var argumentsValue: [String] = []
  private var timeoutSecondsValue = 0

  func record(executableURL: URL, arguments: [String], timeoutSeconds: Int) {
    lock.lock()
    executableURLValue = executableURL
    argumentsValue = arguments
    timeoutSecondsValue = timeoutSeconds
    lock.unlock()
  }

  func snapshot() -> Snapshot {
    lock.lock()
    let snapshot = Snapshot(
      executableURL: executableURLValue,
      arguments: argumentsValue,
      timeoutSeconds: timeoutSecondsValue
    )
    lock.unlock()
    return snapshot
  }
}

struct RemoteExecutionClientTests {
  @Test func remoteExecutionBuildsExpectedSSHArguments() async throws {
    let recorder = RemoteExecutionCallRecorder()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runWithTimeoutImpl: { executableURL, arguments, _, timeoutSeconds in
        recorder.record(
          executableURL: executableURL,
          arguments: arguments,
          timeoutSeconds: timeoutSeconds
        )
        return ShellOutput(stdout: "ok", stderr: "", exitCode: 0)
      }
    )
    let client = RemoteExecutionClient.live(shellClient: shell)
    let profile = SSHHostProfile(
      displayName: "host",
      host: "example.com",
      user: "dev",
      port: 2222,
      authMethod: .publicKey
    )

    let output = try await client.run(profile, "tmux list-sessions", 8)

    #expect(output.exitCode == 0)
    #expect(output.stdout == "ok")

    let snapshot = recorder.snapshot()
    #expect(snapshot.executableURL?.path == "/usr/bin/ssh")
    #expect(snapshot.arguments.contains("dev@example.com"))
    #expect(snapshot.arguments.contains("-p"))
    #expect(snapshot.arguments.contains("2222"))
    #expect(snapshot.arguments.contains("-o"))
    #expect(snapshot.arguments.contains("BatchMode=yes"))
    #expect(snapshot.arguments.last == "tmux list-sessions")
    #expect(snapshot.timeoutSeconds == 8)
  }
}
