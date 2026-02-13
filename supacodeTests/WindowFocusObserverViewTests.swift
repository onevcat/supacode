import AppKit
import Testing

@testable import supacode

@MainActor
struct WindowFocusObserverViewTests {
  @Test func notifyCurrentStateWithoutWindowReportsFalseForBothSignals() {
    let observer = WindowFocusObserverNSView()
    var keyValues: [Bool] = []
    var occlusionValues: [Bool] = []

    observer.onWindowKeyChanged = { keyValues.append($0) }
    observer.onWindowOcclusionChanged = { occlusionValues.append($0) }

    observer.notifyCurrentState()

    #expect(keyValues == [false])
    #expect(occlusionValues == [false])
  }
}
