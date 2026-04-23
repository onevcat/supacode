import Foundation
import Sentry
import Testing

@testable import supacode

struct SentryEventFilterTests {
  @Test func nonHangEventPassesThrough() {
    let event = makeEvent(mechanismType: "nsexception", frames: [])
    #expect(SentryEventFilter.filterSystemHang(event) === event)
  }

  @Test func appHangWithSystemSignatureAndNoAppFrameIsDropped() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "mach_msg2_trap", inApp: false),
        makeFrame(function: "_NSMenuBarDisplayManagerActiveSpaceChanged", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) == nil)
  }

  @Test func appHangWithAnyAppFrameIsKept() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "_NSMenuBarDisplayManagerActiveSpaceChanged", inApp: false),
        makeFrame(function: "WorktreeTerminalManager.didReceiveNotification", inApp: true),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) === event)
  }

  @Test func appHangWithSkyLightEventLoopIdleIsDropped() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "mach_msg2_trap", inApp: false),
        makeFrame(function: "CGSSnarfAndDispatchDatagrams", inApp: false),
        makeFrame(function: "SLSGetNextEventRecordInternal", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) == nil)
  }

  @Test func appHangWithKeyboardLayoutInitIsDropped() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "OpenCCFFile", inApp: false),
        makeFrame(function: "InitializeInputSourceCache", inApp: false),
        makeFrame(function: "TSMCurrentKeyboardLayoutInputSourceRefCreate.cold.1", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) == nil)
  }

  @Test func appHangWithSFSymbolLoadIsDropped() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "-[NSImage bestRepresentationForHints:]", inApp: false),
        makeFrame(function: "-[NSImageSymbolRepProvider init]", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) == nil)
  }

  @Test func appHangWithRunningBoardXPCIsDropped() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "_RBSXPCEncodeObjectForKey", inApp: false),
        makeFrame(function: "-[RBSDomainAttribute encodeWithRBSXPCCoder:]", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) == nil)
  }

  @Test func appHangWithNoKnownSystemSignatureIsKept() {
    let event = makeEvent(
      mechanismType: "AppHang",
      frames: [
        makeFrame(function: "mach_msg2_trap", inApp: false),
        makeFrame(function: "__CFRunLoopRun", inApp: false),
      ]
    )
    #expect(SentryEventFilter.filterSystemHang(event) === event)
  }

  @Test func eventWithoutExceptionsPassesThrough() {
    let event = Event()
    #expect(SentryEventFilter.filterSystemHang(event) === event)
  }

  /// Regression guard for PROWL-MACOS-5 / Sentry issue 7424130201.
  ///
  /// Sentry's `SentryANRTrackerV1` invokes `beforeSend` synchronously from a
  /// background thread. Because the project sets
  /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, un-annotated members of
  /// `SentryEventFilter` are implicitly `@MainActor` and Swift 6.2's executor
  /// check aborts the process via libdispatch when called off-main.
  ///
  /// This test exercises the exact off-main invocation path. If
  /// `filterSystemHang` ever loses `nonisolated`, the `@Sendable` closure below
  /// will fail to compile — turning the runtime crash into a build-time error.
  @Test func filterIsInvokableFromBackgroundThread() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        let event = Event()
        let exception = Exception(value: "test", type: "test")
        exception.mechanism = Mechanism(type: "AppHang")
        let frame = Frame()
        frame.function = "_NSMenuBarDisplayManagerActiveSpaceChanged"
        frame.inApp = NSNumber(value: false)
        exception.stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        event.exceptions = [exception]

        #expect(!Thread.isMainThread)
        #expect(SentryEventFilter.filterSystemHang(event) == nil)
        continuation.resume()
      }
    }
  }

  private func makeEvent(mechanismType: String, frames: [Frame]) -> Event {
    let event = Event()
    let exception = Exception(value: "test", type: "test")
    exception.mechanism = Mechanism(type: mechanismType)
    exception.stacktrace = SentryStacktrace(frames: frames, registers: [:])
    event.exceptions = [exception]
    return event
  }

  private func makeFrame(function: String, inApp: Bool) -> Frame {
    let frame = Frame()
    frame.function = function
    frame.inApp = NSNumber(value: inApp)
    return frame
  }
}
