import Foundation
import Testing

@testable import supacode

private actor RemoteCommandRecorder {
  private var commandsValue: [String] = []

  func append(_ command: String) {
    commandsValue.append(command)
  }

  func commands() -> [String] {
    commandsValue
  }
}

private extension ShellClient {
  static let failing = ShellClient(
    run: { _, _, _ in
      Issue.record("Expected remote endpoint test not to use local shell execution")
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    },
    runLoginImpl: { _, _, _, _ in
      Issue.record("Expected remote endpoint test not to use local login shell execution")
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
  )
}

private extension RemoteExecutionClient {
  static func capturingSuccess(
    stdout: String,
    recorder: RemoteCommandRecorder
  ) -> RemoteExecutionClient {
    RemoteExecutionClient(
      run: { _, command, _ in
        await recorder.append(command)
        return Output(stdout: stdout, stderr: "", exitCode: 0)
      }
    )
  }
}

struct GitClientRemoteCommandTests {
  private let remoteProfile = SSHHostProfile(
    id: "h1",
    displayName: "Server",
    host: "example.com",
    user: "dev",
    authMethod: .publicKey
  )

  @Test func remoteWorktreeListUsesSSHGitCRemotePath() async throws {
    let recorder = RemoteCommandRecorder()
    let client = GitClient(
      shell: .failing,
      remoteExecution: RemoteExecutionClient.capturingSuccess(
        stdout: "",
        recorder: recorder
      )
    )

    _ = try await client.worktrees(
      for: URL(fileURLWithPath: "/synthetic"),
      endpoint: RepositoryEndpoint.remote(hostProfileID: "h1", remotePath: "/srv/repo"),
      hostProfile: remoteProfile
    )

    let commands = await recorder.commands()
    #expect(
      commands.contains(where: {
        $0.contains("git -C '/srv/repo' worktree list")
      })
    )
  }

  @Test func remoteWorktreeCreateUsesSSHGitCRemotePath() async throws {
    let recorder = RemoteCommandRecorder()
    let client = GitClient(
      shell: .failing,
      remoteExecution: RemoteExecutionClient.capturingSuccess(
        stdout: "",
        recorder: recorder
      )
    )

    let stream = client.createWorktreeStream(
      named: "feature/remote",
      in: URL(fileURLWithPath: "/synthetic"),
      baseDirectory: URL(fileURLWithPath: "/srv/worktrees"),
      copyFiles: (ignored: false, untracked: false),
      baseRef: "origin/main",
      endpoint: RepositoryEndpoint.remote(hostProfileID: "h1", remotePath: "/srv/repo"),
      hostProfile: remoteProfile
    )
    for try await _ in stream {}

    let commands = await recorder.commands()
    #expect(
      commands.contains(where: {
        $0.contains("git -C '/srv/repo' worktree add -b feature/remote /srv/worktrees/feature/remote/ origin/main")
          && $0.contains("printf '%s\\n' '/srv/worktrees/feature/remote/'")
      })
    )
  }

  @Test func remoteWorktreeRemoveUsesSSHGitCRemotePath() async throws {
    let recorder = RemoteCommandRecorder()
    let client = GitClient(
      shell: .failing,
      remoteExecution: RemoteExecutionClient.capturingSuccess(
        stdout: "",
        recorder: recorder
      )
    )
    let endpoint = RepositoryEndpoint.remote(hostProfileID: "h1", remotePath: "/srv/repo")
    let worktree = Worktree(
      id: "/srv/worktrees/feature/remote",
      name: "feature/remote",
      detail: "../worktrees/feature/remote",
      workingDirectory: URL(fileURLWithPath: "/srv/worktrees/feature/remote"),
      repositoryRootURL: URL(fileURLWithPath: "/synthetic"),
      endpoint: endpoint
    )

    _ = try await client.removeWorktree(
      worktree,
      deleteBranch: true,
      endpoint: endpoint,
      hostProfile: remoteProfile
    )

    let commands = await recorder.commands()
    #expect(
      commands.contains(where: {
        $0.contains("git -C '/srv/repo' worktree remove --force /srv/worktrees/feature/remote")
      })
    )
    #expect(
      commands.contains(where: {
        $0.contains("git -C '/srv/repo' branch -D feature/remote")
      })
    )
  }
}
