# 066.006 — Canvas completion visibility

## Context and approach

Continue @SunChJ's original commit from #780, resubmitted unchanged as #783.
Keep that commit in the branch history and use #781 as the acknowledgement prerequisite.

The Canvas predicate checks actual keyboard focus and window visibility. A card can
keep those properties while panning moves it completely outside the viewport.
Reproduce that case through AppKit geometry and the completion polling path. If it
fails, require a nonempty visible area before acknowledging a completion. Partial
visibility remains sufficient; no percentage, center-point, or animation gate is added.

Preserve navigation, broadcast input, and worktree-scoped notification semantics.
Test offscreen, partially visible, scaled, and returned panes along with logical-only
focus and inactive-window cases. Verify the combined implementation with #781.

## Outcome

The combined polling test reproduced the report: an offscreen first responder changed
from Working to Idle instead of Done. Its AppKit `visibleRect` was nonempty but entirely
outside its bounds, so checking `visibleRect.isEmpty` alone would not fix the issue.
The predicate now computes the intersection of `bounds` and `visibleRect` and
requires a nonempty result. `CGRect.intersects` alone accepts a zero-area surface
in this environment, so it does not enforce the intended positive-area boundary.

The tests use positive terminal frames, real first-responder transitions, and native
view geometry. Coverage includes clipped ancestor coordinates at 0.5x, 1x, and 2x,
partial intersection, zero area, and leaving/returning to the viewport. Completion
polling and automatic acknowledgement run against the #781 implementation.

## Validation

The final combined Xcode run passed 83 test methods with zero failures and warnings.
`make check` passed, including 146 script tests. The offscreen test failed before
this change and passed afterward. No live-agent GUI session was manually exercised.
