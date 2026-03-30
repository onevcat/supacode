import ComposableArchitecture
import Foundation

struct RemoteTmuxClient: Sendable {
  var listSessions: @Sendable (_ profile: SSHHostProfile, _ timeoutSeconds: Int) async throws -> [String]
  var buildAttachCommand: @Sendable (_ profile: SSHHostProfile, _ sessionName: String, _ remotePath: String) -> String
  var buildCreateAndAttachCommand:
    @Sendable (_ profile: SSHHostProfile, _ preferredName: String, _ remotePath: String) -> String
}

extension RemoteTmuxClient: DependencyKey {
  static let liveValue = live()

  static func live(remoteExecution: RemoteExecutionClient = .liveValue) -> RemoteTmuxClient {
    RemoteTmuxClient(
      listSessions: { profile, timeoutSeconds in
        let output = try await remoteExecution.run(
          profile,
          "tmux list-sessions -F '#S'",
          timeoutSeconds
        )
        if output.exitCode != 0 {
          let stderr = output.stderr.lowercased()
          if stderr.contains("no server running") || stderr.contains("failed to connect to server") {
            return []
          }
          throw RemoteTmuxClientError(
            message: output.stderr.isEmpty ? output.stdout : output.stderr,
            exitCode: output.exitCode
          )
        }
        return output.stdout
          .split(whereSeparator: \.isNewline)
          .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      },
      buildAttachCommand: { profile, sessionName, remotePath in
        let escapedPath = SSHCommandSupport.shellEscape(remotePath)
        let escapedSession = SSHCommandSupport.shellEscape(sessionName)
        let remoteCommand = "cd \(escapedPath) && tmux attach-session -t \(escapedSession)"
        return buildSSHCommand(profile: profile, remoteCommand: remoteCommand)
      },
      buildCreateAndAttachCommand: { profile, preferredName, remotePath in
        let escapedPath = SSHCommandSupport.shellEscape(remotePath)
        let escapedName = SSHCommandSupport.shellEscape(preferredName)
        let ensureSession =
          "(tmux has-session -t \(escapedName) 2>/dev/null || tmux new-session -d -s \(escapedName))"
        let remoteCommand = "cd \(escapedPath) && \(ensureSession) && tmux attach-session -t \(escapedName)"
        return buildSSHCommand(profile: profile, remoteCommand: remoteCommand)
      }
    )
  }

  static let testValue = RemoteTmuxClient(
    listSessions: { _, _ in [] },
    buildAttachCommand: { _, _, _ in "" },
    buildCreateAndAttachCommand: { _, _, _ in "" }
  )
}

extension DependencyValues {
  var remoteTmuxClient: RemoteTmuxClient {
    get { self[RemoteTmuxClient.self] }
    set { self[RemoteTmuxClient.self] = newValue }
  }
}

private nonisolated func buildSSHCommand(
  profile: SSHHostProfile,
  remoteCommand: String
) -> String {
  let endpointKey = [profile.host, profile.user, profile.port.map(String.init) ?? "22"]
    .joined(separator: "|")
  let controlPath = SSHCommandSupport.controlSocketPath(endpointKey: endpointKey)
  let options = SSHCommandSupport.removingBatchMode(
    from: SSHCommandSupport.connectivityOptions(includeBatchMode: true)
  )
  var arguments = options + ["-o", "ControlPath=\(controlPath)", "-t"]
  if let port = profile.port {
    arguments += ["-p", "\(port)"]
  }
  let target = profile.user.isEmpty ? profile.host : "\(profile.user)@\(profile.host)"
  arguments += [target, remoteCommand]
  let shellEscapedArguments = arguments.map(SSHCommandSupport.shellEscape).joined(separator: " ")
  return "/usr/bin/ssh \(shellEscapedArguments)"
}

private nonisolated struct RemoteTmuxClientError: LocalizedError {
  let message: String
  let exitCode: Int32

  var errorDescription: String? {
    "tmux command failed (exit: \(exitCode)): \(message)"
  }
}
