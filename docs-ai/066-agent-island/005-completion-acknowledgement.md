# 066.005 — Completion acknowledgement across session resolution

## Context

PR #781 and the original #778, resubmitted as #782 by @SunChJ, route automatic
acknowledgement through the viewed-surface predicate. A session lookup can suspend
while the user acknowledges a completion and then leaves the window. Deriving read
state from the pre-lookup snapshot can restore Done when session metadata changes.

## Change

After session resolution, merge the current acknowledgement for the same observed
state into the polling result. Preserve its change timestamp. A new working/blocked
to idle transition must still become unread when unviewed; do not treat an earlier
acknowledgement as permission to read future completions. Keep the read policy private.

The implementation uses a per-call session resolver seam and controlled suspension
in behavior tests. Tests cover changed and unchanged session metadata, a new
completion after acknowledgement, and state changes during suspension.

If state other than acknowledgement or its timestamp changed during suspension,
discard the stale poll. The next scheduled poll observes the new state.

## Validation

The controlled suspension test failed on #781 before the fix: Done reappeared and
the acknowledgement timestamp was replaced. It passes with the fix, with and without
new session metadata. Related local tests passed; no live-agent GUI reproduction
was performed for this polling-state change.

## Refs

PR #781; related original implementation #778 and resubmission #782.
