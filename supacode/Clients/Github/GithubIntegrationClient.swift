import ComposableArchitecture

struct GithubIntegrationClient {
  var isAvailable: @MainActor @Sendable () async -> Bool
}

extension GithubIntegrationClient: DependencyKey {
  static let liveValue = GithubIntegrationClient(
    isAvailable: {
      await githubIntegrationIsAvailable()
    }
  )
  static let testValue = GithubIntegrationClient(
    isAvailable: { true }
  )
}

extension DependencyValues {
  var githubIntegration: GithubIntegrationClient {
    get { self[GithubIntegrationClient.self] }
    set { self[GithubIntegrationClient.self] = newValue }
  }
}

@MainActor
private func githubIntegrationIsAvailable() async -> Bool {
  @Shared(.settingsFile) var settingsFile
  @Dependency(GithubCLIClient.self) var githubCLI
  guard settingsFile.global.githubIntegrationEnabled else { return false }
  return await githubCLI.isAvailable()
}
