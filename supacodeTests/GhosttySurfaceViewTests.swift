import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct GhosttySurfaceViewTests {
  @Test func occlusionStateResendsDesiredValueAfterAttachmentChange() {
    var state = GhosttySurfaceView.OcclusionState()

    let firstApply = state.prepareToApply(true)
    let secondApply = state.prepareToApply(true)

    #expect(firstApply)
    #expect(!secondApply)
    let desired = state.invalidateForAttachmentChange()
    let reapply = state.prepareToApply(true)

    #expect(desired == true)
    #expect(reapply)
  }

  @Test func occlusionStateDoesNotResendBeforeAnyDesiredValueExists() {
    var state = GhosttySurfaceView.OcclusionState()

    let desired = state.invalidateForAttachmentChange()
    let firstApply = state.prepareToApply(false)
    let secondApply = state.prepareToApply(false)

    #expect(desired == nil)
    #expect(firstApply)
    #expect(!secondApply)
  }

  @Test func occlusionStateStoresDesiredValueWithoutMarkingItApplied() {
    var state = GhosttySurfaceView.OcclusionState()

    state.setDesired(true)
    let firstApply = state.prepareToApply(true)
    let secondApply = state.prepareToApply(true)

    #expect(firstApply)
    #expect(!secondApply)
  }

  @Test func occlusionStateUsesLatestDeferredDesiredValue() {
    var state = GhosttySurfaceView.OcclusionState()

    state.setDesired(true)
    state.setDesired(false)
    let applyDeferredValue = state.prepareToApply(false)
    let secondApply = state.prepareToApply(false)

    #expect(applyDeferredValue)
    #expect(!secondApply)
  }

  @Test func occlusionStateAppliesLatestValueAfterAttachmentInvalidation() {
    var state = GhosttySurfaceView.OcclusionState()

    let firstApply = state.prepareToApply(true)
    let desiredAfterAttachmentChange = state.invalidateForAttachmentChange()
    #expect(firstApply)
    #expect(desiredAfterAttachmentChange == true)

    state.setDesired(false)
    let applyLatestValue = state.prepareToApply(false)
    let duplicateApply = state.prepareToApply(false)

    #expect(applyLatestValue)
    #expect(!duplicateApply)
  }

  @Test func occlusionStateRetainsLatestDesiredValueAcrossMultipleAttachmentChanges() {
    var state = GhosttySurfaceView.OcclusionState()

    state.setDesired(true)
    let desiredAfterFirstAttachmentChange = state.invalidateForAttachmentChange()
    #expect(desiredAfterFirstAttachmentChange == true)
    state.setDesired(false)
    let desiredAfterSecondAttachmentChange = state.invalidateForAttachmentChange()
    #expect(desiredAfterSecondAttachmentChange == false)

    let applyLatestValue = state.prepareToApply(false)
    let duplicateApply = state.prepareToApply(false)

    #expect(applyLatestValue)
    #expect(!duplicateApply)
  }

  @Test func occlusionDoesNotApplyUntilViewHasSuperviewAndWindow() async {
    let runtime = GhosttyRuntime()
    let surfaceView = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    var appliedValues: [Bool] = []
    surfaceView.onOcclusionAppliedForTesting = { appliedValues.append($0) }
    var attachmentState = (hasSuperview: false, hasWindow: false)
    surfaceView.attachmentStateForTesting = { attachmentState }

    surfaceView.setOcclusion(true)
    await drainMainQueue()
    #expect(appliedValues.isEmpty)

    attachmentState = (hasSuperview: true, hasWindow: false)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()
    #expect(appliedValues.isEmpty)

    attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()
    #expect(appliedValues == [true])
  }

  @Test func occlusionAppliesLatestDeferredValueAfterWindowReattachment() async {
    let runtime = GhosttyRuntime()
    let surfaceView = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    var appliedValues: [Bool] = []
    surfaceView.onOcclusionAppliedForTesting = { appliedValues.append($0) }
    var attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.attachmentStateForTesting = { attachmentState }

    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()
    #expect(appliedValues.isEmpty)

    surfaceView.setOcclusion(true)
    await drainMainQueue()
    #expect(appliedValues == [true])

    attachmentState = (hasSuperview: false, hasWindow: false)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()

    // Occluding (false) applies immediately even while detached to stop
    // the render loop.  Un-occluding (true) is deferred until reattached.
    surfaceView.setOcclusion(false)
    surfaceView.setOcclusion(true)
    surfaceView.setOcclusion(false)
    await drainMainQueue()
    #expect(appliedValues == [true, false])

    attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()
    // Reattachment re-applies the desired value (false) even though it
    // was already applied, because invalidateForAttachmentChange clears
    // the applied cache.
    #expect(appliedValues == [true, false, false])
  }

  @Test func occlusionFalseAppliesImmediatelyWithoutViewAttachment() async {
    let runtime = GhosttyRuntime()
    let surfaceView = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    var appliedValues: [Bool] = []
    surfaceView.onOcclusionAppliedForTesting = { appliedValues.append($0) }
    var attachmentState = (hasSuperview: false, hasWindow: false)
    surfaceView.attachmentStateForTesting = { attachmentState }

    // Occluding without a view hierarchy applies immediately (stops the
    // Metal render loop for restored surfaces that are never displayed).
    surfaceView.setOcclusion(false)
    await drainMainQueue()
    #expect(appliedValues == [false])

    // Un-occluding without a view hierarchy is deferred.
    surfaceView.setOcclusion(true)
    await drainMainQueue()
    #expect(appliedValues == [false])

    // Once attached, the deferred un-occlude is applied.
    attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()
    #expect(appliedValues == [false, true])
  }

  @Test func occlusionCanRecoverWhenAttachmentCallbackIsMissedAfterReattachment() async {
    let runtime = GhosttyRuntime()
    let surfaceView = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    var appliedValues: [Bool] = []
    surfaceView.onOcclusionAppliedForTesting = { appliedValues.append($0) }
    var attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.attachmentStateForTesting = { attachmentState }

    surfaceView.setOcclusion(true)
    await drainMainQueue()
    #expect(appliedValues == [true])

    attachmentState = (hasSuperview: false, hasWindow: false)
    surfaceView.handleAttachmentChangeForTesting()
    await drainMainQueue()

    attachmentState = (hasSuperview: true, hasWindow: true)
    surfaceView.resumeDeferredOcclusionIfNeededForTesting()
    await drainMainQueue()
    #expect(appliedValues == [true, true])
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }

  @Test func normalizedWorkingDirectoryPathRemovesTrailingSlashForNonRootPath() {
    #expect(
      GhosttySurfaceView.normalizedWorkingDirectoryPath("/Users/onevcat/Sync/github/supacode/")
        == "/Users/onevcat/Sync/github/supacode"
    )
    #expect(
      GhosttySurfaceView.normalizedWorkingDirectoryPath("/Users/onevcat/Sync/github/supacode///")
        == "/Users/onevcat/Sync/github/supacode"
    )
  }

  @Test func normalizedWorkingDirectoryPathKeepsRootPath() {
    #expect(GhosttySurfaceView.normalizedWorkingDirectoryPath("/") == "/")
  }

  @Test func accessibilityLineCountsLineBreaksUpToIndex() {
    let content = "alpha\nbeta\ngamma"

    #expect(GhosttySurfaceView.accessibilityLine(for: 0, in: content) == 0)
    #expect(GhosttySurfaceView.accessibilityLine(for: 5, in: content) == 0)
    #expect(GhosttySurfaceView.accessibilityLine(for: 6, in: content) == 1)
    #expect(GhosttySurfaceView.accessibilityLine(for: content.count, in: content) == 2)
  }

  @Test func accessibilityStringReturnsSubstringForValidRange() {
    let content = "alpha\nbeta"

    #expect(
      GhosttySurfaceView.accessibilityString(
        for: NSRange(location: 6, length: 4),
        in: content
      ) == "beta"
    )
    #expect(
      GhosttySurfaceView.accessibilityString(
        for: NSRange(location: 99, length: 1),
        in: content
      ) == nil
    )
  }

  @Test func keyboardLayoutChangeKeyUpSuppressionSuppressesMatchingKeyUp() {
    let suppression = GhosttySurfaceView.KeyboardLayoutChangeKeyUpSuppression(
      keyCode: 49,
      timestamp: 10
    )

    #expect(suppression.suppresses(keyCode: 49, timestamp: 10.1))
    #expect(!suppression.isExpired(at: 10.1))
  }

  @Test func keyboardLayoutChangeKeyUpSuppressionIgnoresDifferentKeyUp() {
    let suppression = GhosttySurfaceView.KeyboardLayoutChangeKeyUpSuppression(
      keyCode: 49,
      timestamp: 10
    )

    #expect(!suppression.suppresses(keyCode: 50, timestamp: 10.1))
    #expect(suppression.suppresses(keyCode: 49, timestamp: 10.2))
    #expect(!suppression.isExpired(at: 10.1))
  }

  @Test func keyboardLayoutChangeKeyUpSuppressionExpires() {
    let suppression = GhosttySurfaceView.KeyboardLayoutChangeKeyUpSuppression(
      keyCode: 49,
      timestamp: 10
    )

    #expect(!suppression.suppresses(keyCode: 49, timestamp: 11.1))
    #expect(suppression.isExpired(at: 11.1))
  }
}
