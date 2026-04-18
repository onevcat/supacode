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
