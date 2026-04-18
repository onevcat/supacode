import ComposableArchitecture
import Sparkle

private let updaterLogger = SupaLogger("Updater")

struct UpdaterClient {
  var configure: @MainActor @Sendable (_ checks: Bool, _ downloads: Bool, _ checkInBackground: Bool) -> Void
  var setUpdateChannel: @MainActor @Sendable (UpdateChannel) -> Void
  var checkForUpdates: @MainActor @Sendable () -> Void
  var events: @MainActor @Sendable () -> AsyncStream<Event>
}

extension UpdaterClient {
  enum Event: Equatable, Sendable {
    case silentUpdateFound(version: String?)
  }
}

@MainActor
final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
  var updateChannel: UpdateChannel = .stable

  nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    // Tip channel is no longer published separately; treat it the same as stable.
    []
  }
}

/// Custom Sparkle user driver that turns background "update found" prompts into a silent signal,
/// while forwarding user-initiated flows to the standard Sparkle UI.
@MainActor
final class SilentUpdateDriver: NSObject, SPUUserDriver {
  private let standard: SPUStandardUserDriver
  private var continuation: AsyncStream<UpdaterClient.Event>.Continuation?

  init(hostBundle: Bundle) {
    self.standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
    super.init()
  }

  func setContinuation(_ continuation: AsyncStream<UpdaterClient.Event>.Continuation) {
    self.continuation?.finish()
    self.continuation = continuation
  }

  nonisolated func show(
    _ request: SPUUpdatePermissionRequest,
    reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void
  ) {
    MainActor.assumeIsolated {
      standard.show(request, reply: reply)
    }
  }

  nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping @Sendable () -> Void) {
    MainActor.assumeIsolated {
      standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }
  }

  nonisolated func showUpdateFound(
    with appcastItem: SUAppcastItem,
    state: SPUUserUpdateState,
    reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
  ) {
    MainActor.assumeIsolated {
      if state.userInitiated {
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
        return
      }
      // Background check: surface the availability silently, then defer so Sparkle
      // will re-offer the same update on the next (user-initiated) check.
      continuation?.yield(.silentUpdateFound(version: appcastItem.displayVersionString))
      reply(.dismiss)
    }
  }

  nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    MainActor.assumeIsolated {
      standard.showUpdateReleaseNotes(with: downloadData)
    }
  }

  nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
    MainActor.assumeIsolated {
      standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }
  }

  nonisolated func showUpdateNotFoundWithError(
    _ error: any Error,
    acknowledgement: @escaping @Sendable () -> Void
  ) {
    MainActor.assumeIsolated {
      standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }
  }

  nonisolated func showUpdaterError(
    _ error: any Error,
    acknowledgement: @escaping @Sendable () -> Void
  ) {
    MainActor.assumeIsolated {
      standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }
  }

  nonisolated func showDownloadInitiated(cancellation: @escaping @Sendable () -> Void) {
    MainActor.assumeIsolated {
      standard.showDownloadInitiated(cancellation: cancellation)
    }
  }

  nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    MainActor.assumeIsolated {
      standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }
  }

  nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
    MainActor.assumeIsolated {
      standard.showDownloadDidReceiveData(ofLength: length)
    }
  }

  nonisolated func showDownloadDidStartExtractingUpdate() {
    MainActor.assumeIsolated {
      standard.showDownloadDidStartExtractingUpdate()
    }
  }

  nonisolated func showExtractionReceivedProgress(_ progress: Double) {
    MainActor.assumeIsolated {
      standard.showExtractionReceivedProgress(progress)
    }
  }

  nonisolated func showReady(toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
    MainActor.assumeIsolated {
      standard.showReady(toInstallAndRelaunch: reply)
    }
  }

  nonisolated func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping @Sendable () -> Void
  ) {
    MainActor.assumeIsolated {
      standard.showInstallingUpdate(
        withApplicationTerminated: applicationTerminated,
        retryTerminatingApplication: retryTerminatingApplication
      )
    }
  }

  nonisolated func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool,
    acknowledgement: @escaping @Sendable () -> Void
  ) {
    MainActor.assumeIsolated {
      standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
  }

  nonisolated func showUpdateInFocus() {
    MainActor.assumeIsolated {
      standard.showUpdateInFocus()
    }
  }

  nonisolated func dismissUpdateInstallation() {
    MainActor.assumeIsolated {
      standard.dismissUpdateInstallation()
    }
  }
}

extension UpdaterClient: DependencyKey {
  static let liveValue: UpdaterClient = {
    let hostBundle = Bundle.main
    let delegate = SparkleUpdateDelegate()
    let driver = SilentUpdateDriver(hostBundle: hostBundle)
    let updater = SPUUpdater(
      hostBundle: hostBundle,
      applicationBundle: hostBundle,
      userDriver: driver,
      delegate: delegate
    )
    do {
      try updater.start()
    } catch {
      updaterLogger.warning("SPUUpdater start failed: \(String(describing: error))")
    }
    return UpdaterClient(
      configure: { checks, _, checkInBackground in
        updater.automaticallyChecksForUpdates = checks
        // Silent update flow requires Sparkle to always prompt us via `showUpdateFound`
        // so we can decide whether to surface the toolbar button. Auto-download would
        // bypass that callback, so we force it off regardless of user preference.
        updater.automaticallyDownloadsUpdates = false
        if checkInBackground, checks {
          updater.checkForUpdatesInBackground()
        }
      },
      setUpdateChannel: { channel in
        delegate.updateChannel = channel
        updater.updateCheckInterval = 3600
        if updater.automaticallyChecksForUpdates {
          updater.checkForUpdatesInBackground()
        }
      },
      checkForUpdates: {
        updater.checkForUpdates()
      },
      events: {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        driver.setContinuation(continuation)
        return stream
      }
    )
  }()

  static let testValue = UpdaterClient(
    configure: { _, _, _ in },
    setUpdateChannel: { _ in },
    checkForUpdates: {},
    events: { AsyncStream { _ in } }
  )
}

extension DependencyValues {
  var updaterClient: UpdaterClient {
    get { self[UpdaterClient.self] }
    set { self[UpdaterClient.self] = newValue }
  }
}
