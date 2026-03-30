import AppKit
import Foundation
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

  @Test func setPinnedSizePreservesUserScrollbackPosition() throws {
    let runtime = GhosttyRuntime()
    let worktree = Worktree(
      id: "/tmp/repo/wt",
      name: "wt",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
    let state = WorktreeTerminalState(runtime: runtime, worktree: worktree)
    let tabId = try #require(state.createTab())
    let surfaceView = try #require(state.surfaceView(for: tabId))
    let scrollWrapper = GhosttySurfaceScrollView(surfaceView: surfaceView)
    scrollWrapper.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    scrollWrapper.layoutSubtreeIfNeeded()
    surfaceView.updateCellSize(width: 10, height: 10)
    scrollWrapper.updateScrollbar(total: 100, offset: 0, length: 10)
    scrollWrapper.layoutSubtreeIfNeeded()

    let scrollView = try #require(scrollWrapper.subviews.first as? NSScrollView)
    scrollView.contentView.scroll(to: CGPoint(x: 0, y: 200))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    let scrolledY = scrollView.contentView.documentVisibleRect.origin.y
    #expect(scrolledY == 200)

    scrollWrapper.setPinnedSize(CGSize(width: 320, height: 200))

    let updatedY = scrollView.contentView.documentVisibleRect.origin.y
    #expect(abs(updatedY - scrolledY) < 0.5)
  }
}
