import Testing

@testable import supacode

struct SSHCommandSupportTests {
  @Test func controlSocketPathFallsBackToTmpWhenTooLong() {
    let path = SSHCommandSupport.controlSocketPath(endpointKey: String(repeating: "x", count: 512))
    #expect(path.hasPrefix("/tmp/"))
    #expect(path.hasSuffix(".sock"))
    #expect(path.utf8.count <= 64)
  }

  @Test func removingBatchModeStripsOnlyBatchModePairs() {
    let filtered = SSHCommandSupport.removingBatchMode(from: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8"])
    #expect(filtered == ["-o", "ConnectTimeout=8"])
  }
}
