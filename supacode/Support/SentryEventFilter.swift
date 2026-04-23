import Foundation
import Sentry

/// Client-side filter for Sentry events.
///
/// Wired into `SentrySDK.start { options.beforeSend = SentryEventFilter.filterSystemHang }`.
///
/// Members are explicitly `nonisolated`: Sentry invokes `beforeSend` synchronously
/// from its own background threads (notably `SentryANRTrackerV1`'s detection thread).
/// Under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, any
/// un-annotated member would implicitly be `@MainActor`, and Swift 6.2's executor
/// check aborts the process via libdispatch when such code runs off the main thread.
enum SentryEventFilter {
  /// Known stack frame function-name fragments that indicate a system-induced
  /// App Hang (wake-from-sleep, active space change, external display connect,
  /// menu bar redraw, etc.). These hangs are observable but have no app-level
  /// remedy — filter them out to avoid drowning real hangs in noise.
  ///
  /// Matched via substring containment, so prefer distinctive fragments that
  /// won't collide with app code.
  nonisolated static let systemHangSignatures = [
    // Menu bar rebuild on active-space change / wake-from-sleep.
    "_NSMenuBarDisplayManagerActiveSpaceChanged",
    "NSMenuBarLocalDisplayWindow",
    "NSMenuBarPresentationInstance",
    "NSMenuBarReplicantWindow",
    // SkyLight window-server event delivery. When the main run loop is idle
    // waiting on the WindowServer mach port, SentryANRTracker can sample the
    // thread mid-mach_msg and misreport the wait as a hang.
    "CGSSnarfAndDispatchDatagrams",
    "SLSGetNextEventRecordInternal",
    "_CGSFindWindow",
    "SLSFindWindowAndOwner",
    // HIToolbox keyboard layout / input-source cache first-touch init. First
    // query after boot or after a layout change walks the component catalog
    // on the main thread.
    "TSMCurrentKeyboardLayoutInputSourceRefCreate",
    "InitializeInputSourceCache",
    // SF Symbol image-rep loading on first access of a given symbol.
    "NSImageSymbolRepProvider",
    // RunningBoardServices XPC encoding on process-state transitions
    // (e.g. assertion renewal); the main thread blocks on the XPC round trip.
    "_RBSXPCEncodeObjectForKey",
    "RBSDomainAttribute",
  ]

  /// Drop App Hang events whose stack contains zero in-app frames AND matches
  /// at least one known system signature. Conservative by design: if the hang
  /// involves any app code, keep it; if the stack is all-system but matches no
  /// known pattern, keep it too (so we still see novel system-level issues).
  nonisolated static func filterSystemHang(_ event: Event) -> Event? {
    guard let exception = event.exceptions?.first,
      exception.mechanism?.type == "AppHang"
    else {
      return event
    }
    let frames = exception.stacktrace?.frames ?? []
    let hasAppFrame = frames.contains { $0.inApp?.boolValue == true }
    let hasSystemSignature = frames.contains { frame in
      guard let function = frame.function else { return false }
      return systemHangSignatures.contains { function.contains($0) }
    }
    if !hasAppFrame && hasSystemSignature {
      return nil
    }
    return event
  }
}
