# Canvas Exit Terminal Blank Tracking

Last updated: 2026-04-11
Status: Open, intermittent, likely long-lived native state issue

## Symptom

When leaving Canvas and returning to the normal worktree terminal view, the terminal area can appear blank.

Typical behavior:

- The normal terminal view is visible in SwiftUI.
- The selected worktree and tab are correct.
- The terminal becomes visible again only after switching to another tab and back.

## Reproduction Profile

Current evidence suggests this is not a fresh-session deterministic bug.

- In a newly launched Prowl session, the bug is difficult to reproduce.
- After the app has been running for a long time, especially across system sleep/wake, the bug may start happening.
- Once it starts happening in a given app session, it tends to reproduce reliably on every Canvas exit until the app is restarted.

This strongly suggests a sticky stale state in the long-lived terminal/native view stack rather than a simple `toggleCanvas` reducer bug.

## Relevant Areas

- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- `supacode/Features/App/Reducer/AppFeature.swift`
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- `supacode/Features/Terminal/Views/WorktreeTerminalTabsView.swift`
- `supacode/Features/Terminal/Views/WindowFocusObserverView.swift`
- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
- `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift`
- `supacode/Features/Canvas/Views/CanvasView.swift`

## Repair History

Known commits that attempted to address this family of issues:

- `161f38a0` Fix blank surface when exiting canvas via toggle shortcut
- `516103e4` fix: invalidate occlusion cache when exiting canvas to prevent blank surfaces
- `11e7d16c` Fix occlusion cache invalidation on surface reattachment
- `7ed53813` fix: defer occlusion apply until surface is attached
- `26273089` fix: simplify canvas exit occlusion handling
- `d4e59155` Add canvas exit terminal diagnostics and occlusion refresh
- `e2a29b2c` test: cover Ghostty attachment occlusion behavior
- `32f51451` Fix canvas exit terminal occlusion recovery

Relevant changelog entries:

- `2026.4.2`: occlusion restored whenever a surface is reattached
- `2026.4.5`: surface state refreshed immediately on Canvas exit
- current unreleased `main`: occlusion recovery also resumes from `updateSurfaceSize()`

## Current Working Theory

The highest-probability root cause is a stale native terminal surface state after reparenting, likely amplified by long app lifetime and sleep/wake transitions.

Current best hypothesis:

- Exiting Canvas causes `GhosttySurfaceView` to be reattached into the normal terminal hierarchy.
- Reparenting invalidates the occlusion-applied cache.
- In some sessions, especially after sleep/wake, the expected "surface is ready again, now reapply visible occlusion" chain does not complete reliably.
- SwiftUI has already switched back to the normal terminal view, but Ghostty's renderer remains effectively paused or not fully resumed for that surface.
- Switching tabs forces another round of visibility/focus activity, which recovers the surface.

What is less likely at this point:

- Wrong worktree selection
- Wrong selected tab restoration
- Basic reducer ordering bug in `toggleCanvas`

Those paths have been observed as correct in diagnostic logs while the surface still remained blank.

## Logs Added For Ongoing Investigation

Two log markers should be collected together:

- `[CanvasExit]`
- `[TerminalWake]`

### `[CanvasExit]`

Existing and previous diagnostics already cover:

- `WorktreeTerminalTabsView.onAppear`
- surface attachment changes
- deferred occlusion
- reapply occlusion
- selected worktree transition when leaving Canvas

### `[TerminalWake]`

Added on 2026-04-11 to correlate future failures with sleep/wake and long-lived surface state:

- `GhosttyRuntime`
  - `workspaceWillSleep`
  - `workspaceDidWake`
  - `screensDidSleep`
  - `screensDidWake`
  - runtime surface count
- `GhosttySurfaceView`
  - per-surface state snapshot on workspace sleep/wake
  - per-surface state snapshot on `viewDidMoveToWindow`
  - per-surface state snapshot on `viewDidMoveToSuperview`
- `WindowFocusObserverView`
  - window activity changes (`key`, `visible`, `force`, `windowNumber`)

Per-surface wake logs include:

- `surface`
- `hasSurface`
- `attached`
- `window`
- `desired`
- `focused`
- `firstResponder`
- `bounds`
- `backing`
- `windowVisible`
- `windowKey`

## How To Collect Logs

Use `make log-stream`, then reproduce the issue and save the section covering:

- the last successful Canvas exit before the bug starts
- the first failed Canvas exit after the bug starts
- any sleep/wake events before that failure

If filtering manually, focus on lines containing:

- `[CanvasExit]`
- `[TerminalWake]`

If using `log stream` directly, a useful predicate is:

```bash
log stream --style compact \
  --predicate 'subsystem == "com.onevcat.prowl" && (eventMessage CONTAINS[c] "[CanvasExit]" || eventMessage CONTAINS[c] "[TerminalWake]")'
```

## What To Compare Next Time

When the bug reproduces again, compare a healthy exit and a broken exit for:

- whether `workspaceDidWake` or `screensDidWake` happened shortly before failures started
- whether the affected surface reports `desired=Optional(true)` but never logs `reapplyOcclusion`
- whether `WindowFocusObserverView` still reports the window as visible/key when the blank terminal is shown
- whether the affected surface is attached to a superview and window but still does not recover
- whether `bounds` and `backing` stop changing for the affected surface while the view is visibly present

## Open Questions

- Is sleep/wake the true trigger, or just the most common way to enter the stale state?
- Is the bad state owned by `GhosttySurfaceView`, underlying `ghostty_surface_t`, or AppKit/Metal attachment?
- Does the failure always affect the same surface instance for a worktree, or any surface after the session becomes "poisoned"?
- Would an explicit post-wake surface refresh solve the actual root cause, or only mask a lower-level Ghostty/AppKit lifecycle issue?

## Next Step Candidates

Do not do these preemptively unless new logs support them:

- add explicit post-wake repair for all active surfaces
- force-resend occlusion and size after wake
- force content-scale/display-id refresh after wake
- invalidate more cached state after wake, not only after attachment changes

## Notes

This document should be updated every time:

- a new hypothesis is formed
- a new instrumentation point is added
- a repro pattern changes
- a candidate fix is attempted
- a failed fix is ruled out
