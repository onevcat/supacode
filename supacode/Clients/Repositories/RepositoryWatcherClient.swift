import ComposableArchitecture
import Foundation

struct RepositoryWatcherClient {
  var watch: @Sendable (URL) -> AsyncStream<Void>
}

extension RepositoryWatcherClient: DependencyKey {
  static let liveValue = RepositoryWatcherClient { rootURL in
    AsyncStream { continuation in
      Task { @MainActor in
        let watcher = RepositoryChangeWatcher(rootURL: rootURL) {
          continuation.yield(())
        }
        continuation.onTermination = { _ in
          Task { @MainActor in
            watcher.stop()
          }
        }
      }
    }
  }

  static let testValue = RepositoryWatcherClient { _ in
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

extension DependencyValues {
  var repositoryWatcher: RepositoryWatcherClient {
    get { self[RepositoryWatcherClient.self] }
    set { self[RepositoryWatcherClient.self] = newValue }
  }
}
