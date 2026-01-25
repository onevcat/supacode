import ComposableArchitecture
import Sparkle

struct UpdaterClient {
  var configure: @MainActor @Sendable (_ checks: Bool, _ downloads: Bool, _ checkInBackground: Bool) -> Void
  var checkForUpdates: @MainActor @Sendable () -> Void
}

extension UpdaterClient: DependencyKey {
  static let liveValue: UpdaterClient = {
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    let updater = controller.updater
    return UpdaterClient(
      configure: { checks, downloads, checkInBackground in
        _ = controller
        updater.automaticallyChecksForUpdates = checks
        updater.automaticallyDownloadsUpdates = downloads
        if checkInBackground, checks {
          updater.checkForUpdatesInBackground()
        }
      },
      checkForUpdates: {
        _ = controller
        updater.checkForUpdates()
      }
    )
  }()

  static let testValue = UpdaterClient(
    configure: { _, _, _ in },
    checkForUpdates: { }
  )
}

extension DependencyValues {
  var updaterClient: UpdaterClient {
    get { self[UpdaterClient.self] }
    set { self[UpdaterClient.self] = newValue }
  }
}
