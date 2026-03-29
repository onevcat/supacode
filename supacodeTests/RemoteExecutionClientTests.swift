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
  private var snapshots: [Snapshot] = []

  func record(executableURL: URL, arguments: [String], timeoutSeconds: Int) {
    lock.lock()
    snapshots.append(
      Snapshot(
        executableURL: executableURL,
        arguments: arguments,
        timeoutSeconds: timeoutSeconds
      )
    )
    lock.unlock()
  }

  func snapshot() -> Snapshot {
    lock.lock()
    let snapshot = snapshots.last ?? Snapshot(executableURL: nil, arguments: [], timeoutSeconds: 0)
    lock.unlock()
    return snapshot
  }

  func allSnapshots() -> [Snapshot] {
    lock.lock()
    let snapshot = snapshots
    lock.unlock()
    return snapshot
  }
}

nonisolated final class StringRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  func append(_ value: String) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    let snapshot = values
    lock.unlock()
    return snapshot
  }
}

nonisolated final class EnvironmentRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [[String: String]] = []

  func store(_ environment: [String: String]) {
    lock.lock()
    values.append(environment)
    lock.unlock()
  }

  func snapshot() -> [String: String]? {
    lock.lock()
    let snapshot = values.last
    lock.unlock()
    return snapshot
  }

  func allSnapshots() -> [[String: String]] {
    lock.lock()
    let snapshot = values
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

  @Test func passwordAuthUsesAskpassAndLoadsPasswordFromKeychain() async throws {
    let recorder = RemoteExecutionCallRecorder()
    let envRecorder = EnvironmentRecorder()
    let keychainLookups = StringRecorder()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runWithTimeoutImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runWithTimeoutEnvironmentImpl: { executableURL, arguments, _, environment, timeoutSeconds in
        recorder.record(
          executableURL: executableURL,
          arguments: arguments,
          timeoutSeconds: timeoutSeconds
        )
        envRecorder.store(environment)
        return ShellOutput(stdout: "ok", stderr: "", exitCode: 0)
      }
    )
    let client = RemoteExecutionClient.live(
      shellClient: shell,
      keychainClient: KeychainClient(
        savePassword: { _, _ in },
        loadPassword: { key in
          keychainLookups.append(key)
          return "secret"
        },
        deletePassword: { _ in }
      )
    )
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "host",
      host: "example.com",
      user: "dev",
      port: 2222,
      authMethod: .password
    )

    let output = try await client.run(profile, "tmux list-sessions", 8)

    #expect(output.exitCode == 0)
    #expect(output.stdout == "ok")
    #expect(keychainLookups.snapshot() == ["host-1"])

    let snapshot = recorder.snapshot()
    #expect(snapshot.executableURL?.path == "/usr/bin/ssh")
    #expect(snapshot.arguments.contains("dev@example.com"))
    #expect(snapshot.arguments.contains("-p"))
    #expect(snapshot.arguments.contains("2222"))
    #expect(snapshot.arguments.contains("BatchMode=yes"))

    let allCalls = recorder.allSnapshots()
    #expect(allCalls.count == 2)
    if allCalls.count == 2 {
      let bootstrapCall = allCalls[0]
      #expect(bootstrapCall.arguments.contains("PreferredAuthentications=password,keyboard-interactive"))
      #expect(bootstrapCall.arguments.contains("PubkeyAuthentication=no"))
      #expect(bootstrapCall.arguments.contains("NumberOfPasswordPrompts=1"))
      #expect(bootstrapCall.arguments.last == "exit")
      #expect(bootstrapCall.timeoutSeconds == SSHCommandSupport.bootstrapTimeoutSeconds)

      let commandCall = allCalls[1]
      #expect(commandCall.arguments.last == "tmux list-sessions")
      #expect(commandCall.timeoutSeconds == 8)
    }

    let environments = envRecorder.allSnapshots()
    #expect(environments.count == 2)
    if environments.count == 2 {
      let bootstrapEnvironment = environments[0]
      #expect(bootstrapEnvironment["SSH_ASKPASS"] != nil)
      #expect(bootstrapEnvironment["SSH_ASKPASS_REQUIRE"] == "force")
      #expect(bootstrapEnvironment["DISPLAY"] == ":0")
      #expect(bootstrapEnvironment["PROWL_REMOTE_SSH_PASSWORD"] == nil)

      let commandEnvironment = environments[1]
      #expect(commandEnvironment.isEmpty)
    }
  }

  @Test func askpassHelperWritesPasswordToScriptNotEnvironment() throws {
    let support = try SSHCommandSupport.makeAskpassSupport(password: "secret")
    defer {
      try? FileManager.default.removeItem(at: support.helperURL)
    }

    let scriptContents = try String(contentsOf: support.helperURL)
    #expect(scriptContents.contains("secret"))
    #expect(support.environment["DISPLAY"] == ":0")
    #expect(support.environment["SSH_ASKPASS"] == support.helperURL.path(percentEncoded: false))
    #expect(support.environment["SSH_ASKPASS_REQUIRE"] == "force")
    #expect(support.environment["PROWL_REMOTE_SSH_PASSWORD"] == nil)
  }
}
