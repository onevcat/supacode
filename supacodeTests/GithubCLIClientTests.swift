import Foundation
import Testing

@testable import supacode

actor GithubBatchShellProbe {
  private var callCount = 0
  private var inFlight = 0
  private var maxInFlight = 0

  func beginCall() -> Int {
    callCount += 1
    inFlight += 1
    if inFlight > maxInFlight {
      maxInFlight = inFlight
    }
    return callCount
  }

  func endCall() {
    inFlight -= 1
  }

  func snapshot() -> (callCount: Int, maxInFlight: Int) {
    (callCount: callCount, maxInFlight: maxInFlight)
  }
}

struct GithubCLIClientTests {
  @Test func batchPullRequestsCapsConcurrencyAtThree() async throws {
    let probe = GithubBatchShellProbe()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, arguments, _, _ in
        _ = await probe.beginCall()
        do {
          try await Task.sleep(for: .milliseconds(80))
          let stdout = graphQLResponse(for: arguments)
          await probe.endCall()
          return ShellOutput(stdout: stdout, stderr: "", exitCode: 0)
        } catch {
          await probe.endCall()
          throw error
        }
      }
    )
    let client = GithubCLIClient.live(shell: shell)
    let branches = (0..<100).map { "feature-\($0)" }

    _ = try await client.batchPullRequests("github.com", "khoi", "repo", branches)

    let snapshot = await probe.snapshot()
    #expect(snapshot.callCount == 4)
    #expect(snapshot.maxInFlight == 3)
  }

  @Test func batchPullRequestsThrowsWhenAnyChunkFails() async {
    let probe = GithubBatchShellProbe()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, arguments, _, _ in
        let callIndex = await probe.beginCall()
        if callIndex == 2 {
          await probe.endCall()
          throw ShellClientError(
            command: "gh api graphql",
            stdout: "",
            stderr: "boom",
            exitCode: 1
          )
        }
        do {
          try await Task.sleep(for: .milliseconds(40))
          let stdout = graphQLResponse(for: arguments)
          await probe.endCall()
          return ShellOutput(stdout: stdout, stderr: "", exitCode: 0)
        } catch {
          await probe.endCall()
          throw error
        }
      }
    )
    let client = GithubCLIClient.live(shell: shell)
    let branches = (0..<30).map { "feature-\($0)" }

    do {
      _ = try await client.batchPullRequests("github.com", "khoi", "repo", branches)
      Issue.record("Expected batchPullRequests to throw")
    } catch let error as GithubCLIError {
      switch error {
      case .commandFailed:
        break
      case .outdated, .unavailable:
        Issue.record("Unexpected GithubCLIError: \(error.localizedDescription)")
      }
    } catch {
      Issue.record("Unexpected error type: \(error.localizedDescription)")
    }
  }

  @Test func batchPullRequestsDeduplicatesBeforeChunking() async throws {
    let probe = GithubBatchShellProbe()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { _, arguments, _, _ in
        _ = await probe.beginCall()
        let stdout = graphQLResponse(for: arguments)
        await probe.endCall()
        return ShellOutput(stdout: stdout, stderr: "", exitCode: 0)
      }
    )
    let client = GithubCLIClient.live(shell: shell)
    let uniqueBranches = (0..<30).map { "feature-\($0)" }
    let branches = uniqueBranches + ["feature-0", "feature-1", "feature-2", "", ""]

    let result = try await client.batchPullRequests("github.com", "khoi", "repo", branches)

    #expect(result.isEmpty)
    let snapshot = await probe.snapshot()
    #expect(snapshot.callCount == 2)
  }
}

private func graphQLResponse(for arguments: [String]) -> String {
  guard let queryArgument = arguments.first(where: { $0.hasPrefix("query=") }) else {
    return #"{"data":{"repository":{}}}"#
  }
  let query = String(queryArgument.dropFirst("query=".count))
  let aliases = queryAliases(from: query)
  let entries = aliases.map { #""\#($0)":{"nodes":[]}"# }.joined(separator: ",")
  return #"{"data":{"repository":{\#(entries)}}}"#
}

private func queryAliases(from query: String) -> [String] {
  guard let regex = try? NSRegularExpression(pattern: #"branch\d+"#) else {
    return []
  }
  let range = NSRange(query.startIndex..<query.endIndex, in: query)
  var seen = Set<String>()
  var aliases: [String] = []
  for match in regex.matches(in: query, range: range) {
    guard let aliasRange = Range(match.range, in: query) else {
      continue
    }
    let alias = String(query[aliasRange])
    if seen.insert(alias).inserted {
      aliases.append(alias)
    }
  }
  return aliases
}
