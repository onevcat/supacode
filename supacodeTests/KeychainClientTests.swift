import Foundation
import Testing

@testable import supacode

struct KeychainClientTests {
  @Test func keychainRoundTrip() async throws {
    let key = "supacode.tests.ssh.profile.\(UUID().uuidString)"
    let client = KeychainClient.liveValue

    try await client.savePassword("secret", key)
    let loaded = try await client.loadPassword(key)
    #expect(loaded == "secret")
    try await client.deletePassword(key)
    let deleted = try await client.loadPassword(key)
    #expect(deleted == nil)
  }
}
