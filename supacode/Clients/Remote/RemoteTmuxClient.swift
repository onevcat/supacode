import ComposableArchitecture
import Foundation

struct RemoteTmuxClient: Sendable {
  var listSessions: @Sendable (_ profile: SSHHostProfile, _ timeoutSeconds: Int) async throws -> [String]
  var buildAttachCommand: @Sendable (_ sessionName: String, _ remotePath: String) -> String
  var buildCreateAndAttachCommand: @Sendable (_ preferredName: String, _ remotePath: String) -> String
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
      buildAttachCommand: { sessionName, remotePath in
        let escapedPath = SSHCommandSupport.shellEscape(remotePath)
        let escapedSession = SSHCommandSupport.shellEscape(sessionName)
        return "cd \(escapedPath) && tmux attach-session -t \(escapedSession)"
      },
      buildCreateAndAttachCommand: { preferredName, remotePath in
        let escapedPath = SSHCommandSupport.shellEscape(remotePath)
        let escapedName = SSHCommandSupport.shellEscape(preferredName)
        let ensureSession =
          "(tmux has-session -t \(escapedName) 2>/dev/null || tmux new-session -d -s \(escapedName))"
        return "cd \(escapedPath) && \(ensureSession) && tmux attach-session -t \(escapedName)"
      }
    )
  }

  static let testValue = RemoteTmuxClient(
    listSessions: { _, _ in [] },
    buildAttachCommand: { _, _ in "" },
    buildCreateAndAttachCommand: { _, _ in "" }
  )
}

extension DependencyValues {
  var remoteTmuxClient: RemoteTmuxClient {
    get { self[RemoteTmuxClient.self] }
    set { self[RemoteTmuxClient.self] = newValue }
  }
}

private nonisolated struct RemoteTmuxClientError: LocalizedError {
  let message: String
  let exitCode: Int32

  var errorDescription: String? {
    "tmux command failed (exit: \(exitCode)): \(message)"
  }
}
