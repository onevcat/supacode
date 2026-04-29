# Canvas Exit Terminal Blank Closure

Last updated: 2026-04-29
Status: Closed

## Outcome

The Canvas exit / entry blank terminal issue has not reappeared after the host
ownership fix and occlusion reapply safeguards landed. Treat this investigation
as closed unless a new report includes a fresh reproduction pattern.

## Root Cause

The most likely failure mode was host ownership loss during SwiftUI/AppKit
reparenting:

- Canvas and terminal wrappers both host the same `GhosttySurfaceView`.
- A stale terminal wrapper could attempt to reattach a surface that was already
  owned by the live Canvas wrapper.
- When that stale wrapper later deinitialized, AppKit removed the surface again,
  leaving the active host blank even though reducer selection and tab state were
  still correct.

## Fixes Kept

- Terminal hosts only defensively reattach orphaned surfaces; they do not steal a
  surface from another live host.
- Occlusion state invalidates on attachment changes so the latest desired value
  is resent after reattachment.
- Un-occluding is deferred until a surface has both a superview and a window;
  occluding remains immediate so detached surfaces do not keep rendering.
- Canvas-managed terminal states avoid normal window-activity sync while Canvas
  owns visibility.

## Remaining Logs

Most investigation logs were removed. The retained low-frequency logs are:

- `[CanvasExit] enteringCanvas`
- `[CanvasExit] setSelectedWorktreeID`
- `[CanvasExit] deferOcclusion`
- `[CanvasExit] hostReattach`
- `[CanvasExit] hostReattachComplete`
- `[TerminalWake]` runtime sleep/wake summaries

These are enough to identify a regression without keeping wrapper lifecycle,
tab appear/disappear, attachment-change, or call-stack logging in normal builds.

## Residual Risk

The remaining risk is in AppKit view lifecycle ordering. If a future SwiftUI
layout change introduces another host that can own `GhosttySurfaceView`, it must
follow the same rule: only adopt orphaned surfaces and never move a surface away
from another live host.

Relevant coverage:

- `GhosttySurfaceViewTests.terminalHostDoesNotStealSurfaceFromCanvasHost`
- `GhosttySurfaceViewTests.canvasHostDoesNotStealDetachedSurfaceBack`
- `GhosttySurfaceViewTests.terminalHostReattachesSurfaceOnlyAfterItLeavesTheViewTree`
- occlusion reattachment tests in `GhosttySurfaceViewTests`
