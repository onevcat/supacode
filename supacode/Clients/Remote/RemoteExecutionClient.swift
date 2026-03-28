import ComposableArchitecture
import Foundation

struct RemoteExecutionClient: Sendable {
  struct Output: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }

  var run: @Sendable (_ profile: SSHHostProfile, _ command: String, _ timeoutSeconds: Int) async throws -> Output
}

extension RemoteExecutionClient: DependencyKey {
  static let liveValue = live()

  static func live(shellClient: ShellClient = .liveValue) -> RemoteExecutionClient {
    RemoteExecutionClient(
      run: { profile, command, timeoutSeconds in
        let endpointKey = [profile.host, profile.user, profile.port.map(String.init) ?? "22"]
          .joined(separator: "|")
        let controlPath = SSHCommandSupport.controlSocketPath(endpointKey: endpointKey)

        var options = SSHCommandSupport.connectivityOptions(includeBatchMode: profile.authMethod != .password)
        options += ["-o", "ControlPath=\(controlPath)"]

        if let port = profile.port {
          options += ["-p", "\(port)"]
        }

        let target = profile.user.isEmpty ? profile.host : "\(profile.user)@\(profile.host)"
        let arguments = options + [target, command]
        do {
          let output = try await shellClient.runWithTimeout(
            URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments,
            nil,
            timeoutSeconds: timeoutSeconds
          )
          return Output(stdout: output.stdout, stderr: output.stderr, exitCode: output.exitCode)
        } catch let shellError as ShellClientError {
          return Output(
            stdout: shellError.stdout,
            stderr: shellError.stderr,
            exitCode: shellError.exitCode
          )
        }
      }
    )
  }

  static let testValue = RemoteExecutionClient(
    run: { _, _, _ in
      Output(stdout: "", stderr: "", exitCode: 0)
    }
  )
}

extension DependencyValues {
  var remoteExecutionClient: RemoteExecutionClient {
    get { self[RemoteExecutionClient.self] }
    set { self[RemoteExecutionClient.self] = newValue }
  }
}
