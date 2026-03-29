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
}
