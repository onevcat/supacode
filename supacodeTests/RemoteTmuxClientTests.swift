import Testing

@testable import supacode

struct RemoteTmuxClientTests {
  @Test func remoteTmuxParsesSessionNames() async throws {
    let remoteExecution = RemoteExecutionClient(
      run: { _, _, _ in
        .init(stdout: "main\nops\n", stderr: "", exitCode: 0)
      }
    )
    let client = RemoteTmuxClient.live(remoteExecution: remoteExecution)
    let profile = SSHHostProfile(
      displayName: "Host",
      host: "host",
      authMethod: .publicKey
    )

    let sessions = try await client.listSessions(profile, 8)

    #expect(sessions == ["main", "ops"])
  }

  @Test func buildAttachCommandUsesNativeSSHWithControlSocket() {
    let client = RemoteTmuxClient.live()
    let profile = SSHHostProfile(
      id: "host-1",
      displayName: "Host",
      host: "example.com",
      user: "dev",
      port: 2222,
      authMethod: .publicKey
    )

    let command = client.buildAttachCommand(profile, "kn/master", "/home/dev/project")

    #expect(command.contains("/usr/bin/ssh"))
    #expect(command.contains("ControlPath="))
    #expect(command.contains("dev@example.com"))
    #expect(command.contains("tmux attach-session -t"))
    #expect(command.contains("cd '/home/dev/project'"))
  }
}
