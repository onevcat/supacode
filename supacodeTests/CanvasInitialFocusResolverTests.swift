import Foundation
import Testing

@testable import supacode

struct CanvasInitialFocusResolverTests {
  private let tab1 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
  private let tab2 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
  private let tab3 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
  private let surface1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let surface2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
  private let surface3 = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

  @Test func prefersSelectedTabFromPreferredWorktree() {
    let result = CanvasInitialFocusResolver.initialFocus(
      preferredSurfaceID: nil,
      preferredWorktreeID: "repo-2",
      candidates: [
        .init(worktreeID: "repo-1", tabID: tab1, focusedSurfaceID: surface1, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab2, focusedSurfaceID: surface2, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab3, focusedSurfaceID: surface3, isSelectedTab: false),
      ]
    )

    #expect(result?.tabID == tab2)
    #expect(result?.surfaceID == surface2)
  }

  @Test func fallsBackToFirstVisibleTabWhenPreferredWorktreeMissing() {
    let result = CanvasInitialFocusResolver.initialFocus(
      preferredSurfaceID: nil,
      preferredWorktreeID: "missing",
      candidates: [
        .init(worktreeID: "repo-1", tabID: tab1, focusedSurfaceID: surface1, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab2, focusedSurfaceID: surface2, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab3, focusedSurfaceID: surface3, isSelectedTab: false),
      ]
    )

    #expect(result?.tabID == tab1)
    #expect(result?.surfaceID == surface1)
  }

  @Test func fallsBackWhenPreferredWorktreeHasNoSelectedTab() {
    let result = CanvasInitialFocusResolver.initialFocus(
      preferredSurfaceID: nil,
      preferredWorktreeID: "repo-2",
      candidates: [
        .init(worktreeID: "repo-1", tabID: tab1, focusedSurfaceID: surface1, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab2, focusedSurfaceID: surface2, isSelectedTab: false),
        .init(worktreeID: "repo-2", tabID: tab3, focusedSurfaceID: surface3, isSelectedTab: false),
      ]
    )

    #expect(result?.tabID == tab1)
    #expect(result?.surfaceID == surface1)
  }

  @Test func returnsNilWithoutVisibleTabs() {
    let result = CanvasInitialFocusResolver.initialFocus(
      preferredSurfaceID: nil,
      preferredWorktreeID: "repo-1",
      candidates: []
    )

    #expect(result == nil)
  }

  @Test func prefersResponderSurfaceEvenWhenWorktreeFallbackDiffers() {
    let result = CanvasInitialFocusResolver.initialFocus(
      preferredSurfaceID: surface3,
      preferredWorktreeID: "repo-1",
      candidates: [
        .init(worktreeID: "repo-1", tabID: tab1, focusedSurfaceID: surface1, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab2, focusedSurfaceID: surface2, isSelectedTab: true),
        .init(worktreeID: "repo-2", tabID: tab3, focusedSurfaceID: surface3, isSelectedTab: false),
      ]
    )

    #expect(result?.tabID == tab3)
    #expect(result?.surfaceID == surface3)
  }
}
