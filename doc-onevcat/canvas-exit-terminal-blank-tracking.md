# Canvas Exit Terminal Blank Tracking

Last updated: 2026-04-15
Status: Open, intermittent, narrowed from occlusion-only suspicion to host reattachment failure

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
- `supacode/Infrastructure/Ghostty/GhosttyTerminalView.swift`
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
- current branch `fix/canvas-exit-surface-reattach`
  - add detach-intent stack logging before `GhosttySurfaceView` loses its superview/window
  - add wrapper host diagnostics (`hostKind`, wrapper id, surface id)
  - add terminal-only defensive reattach in `GhosttySurfaceScrollView.ensureSurfaceAttached()`
  - add focused tests for terminal-vs-canvas wrapper ownership behavior

Relevant changelog entries:

- `2026.4.2`: occlusion restored whenever a surface is reattached
- `2026.4.5`: surface state refreshed immediately on Canvas exit
- current unreleased `main`: occlusion recovery also resumes from `updateSurfaceSize()`

## Current Working Theory

The highest-probability root cause is no longer "occlusion state got stale while the surface stayed attached".

New evidence from a reduced two-tab repro points to a more concrete failure mode:

- the selected surface (`desired=Optional(true)`, focused, first responder) is briefly attached during Canvas exit
- it reaches the normal terminal layout size
- it is later detached (`attached=false window=false`)
- no subsequent log shows that surface reattached to the final terminal host

This suggests the blank terminal is caused by host ownership loss:

- SwiftUI/AppKit reparenting during Canvas teardown temporarily moves the `GhosttySurfaceView`
- a later teardown or host rebuild removes the surface from the active view tree
- the normal terminal host does not currently guarantee that its `documentView` still owns the surface after updates
- once detached, occlusion recovery is irrelevant because there is no live host left to present the surface

What now looks less likely:

- wrong worktree selection
- wrong selected tab restoration
- pure reducer ordering bug in `toggleCanvas`
- occlusion cache invalidation as the sole root cause

## Logs Added For Ongoing Investigation

Two log markers should be collected together:

- `[CanvasExit]`
- `[TerminalWake]`

### `[CanvasExit]`

Existing and previous diagnostics already cover:

- `WorktreeTerminalTabsView.onAppear`
- `WorktreeTerminalTabsView.onDisappear`
- surface attachment changes
- deferred occlusion
- reapply occlusion
- selected worktree transition when leaving Canvas
- surface detach intent (`viewWillMove(toSuperview:/toWindow:)`) with call stack
- host wrapper lifecycle (`hostMake`, `hostInit`, `hostUpdate`, `hostDeinit`, `hostReattach`)
- host reattach completion snapshot (`hostReattachComplete`)
- per-surface host metadata (`hostKind`, wrapper id)

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
  - detach-time safety-net request back to the last known terminal host
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
- whether the affected surface logs `detachIntent` before going blank, and which stack removes it
- whether a terminal host logs `hostUpdate` but never `hostReattach` for the affected surface
- whether the terminal host does log `hostReattach`, but the surface still remains blank afterward
- whether `WindowFocusObserverView` still reports the window as visible/key when the blank terminal is shown

## Open Questions

- Is sleep/wake the true trigger, or just the most common way to enter the stale state?
- Which host teardown path actually performs the final detach: Canvas wrapper cleanup, terminal wrapper replacement, or another AppKit rebuild?
- If terminal-side defensive reattach works, is it sufficient as the durable fix or just masking a lower-level host lifecycle race?
- If reattach does not work, is the detached native view still valid, or do we need to recreate the underlying `ghostty_surface_t`?

## Next Step Candidates

Do not do these preemptively unless new logs support them:

- widen defensive reattach beyond the normal terminal host
- recreate a surface when host reattach fails
- add explicit post-wake repair for all active surfaces
- force-resend occlusion and size after wake
- force content-scale/display-id refresh after wake

## Notes

This document should be updated every time:

- a new hypothesis is formed
- a new instrumentation point is added
- a repro pattern changes
- a candidate fix is attempted
- a failed fix is ruled out

## 2026-04-15 Snapshot

Latest reduced repro:

- two tabs only
- selected tab surface detached after briefly reaching terminal-sized bounds
- no reattach log observed afterward

Current tactical response:

- add detach stack logging to identify who removes the surface
- add host wrapper diagnostics to correlate `surface ↔ wrapper ↔ canvas/terminal`
- attempt a narrow fix: terminal host reattaches the surface if updates/layout find it missing
- add a detach-time safety net so a just-detached surface asks its last terminal host to try reattachment on the next main-loop turn

Expected interpretation of the next repro:

- if `hostReattach` appears and the terminal becomes visible again, the bug is likely host ownership loss during Canvas teardown
- if `hostReattach` appears but the terminal stays blank, the issue may still involve stale native surface/render state after detach
- if no terminal `hostReattach` appears, the active terminal host may not be rebuilding/updating as expected
