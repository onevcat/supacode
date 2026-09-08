# 063.020 — Additive Handoff Workflow

Status: Implemented; external review and Debug acceptance pending, 2026-09-08.

## Scope and authority

Add one built-in, `prowl.handoff`. Keep the existing handoff HUD, CLI, and execution
path. Do not add `prowl.handoff-checkpoint`, retire legacy commands, or publish a
release. This owner decision supersedes the migration scope of the earlier D3 plan.

## Infrastructure assessment

The runner already provides explicit deliveries, self-initiated first messages,
profile launch, scoped content access, action records, and retry/cancel attention.
HandoffStore and HandoffCoordinator already preserve briefing, generated context,
archives, and session excerpts across Git worktrees, workspaces, and plain directories.
Reuse these boundaries instead of adding a file-operation library or another launcher.

Two small gaps remain: a reusable action to persist a workflow briefing, and profile
admission for a launch branch disabled by immutable start inputs. The latter must agree
between the CLI, start sheet, and machine. Unknown/runtime-dependent conditions remain
conservative; do not predict runtime state or execute actions during admission.

## Workflow

1. The current agent writes a briefing with Objective, Current State, and Next Steps.
   This is the first step so self-initiated runs receive the delivery contract directly.
2. A native `builtin:save-handoff` action validates the briefing and saves it with
   repository/session context under `.prowl/handoff/`, using the existing storage core.
   Keep an immutable, run-specific handoff copy for the receiver, separate from mutable
   `current.md` and expiring workflow history. Validate inputs before writing shared state.
3. An input selects saving only or launching a receiver (default). Launch uses the normal
   profile picker and workflow launch path, without runtime restrictions or pane closure.
   The receiver reads the saved packet and continues the recorded task. Workflow completion
   means the packet was saved and the optional receiver launched, not that its task is done.
4. Report the saved artifact through the workflow result/notification.

Do not require a receiver profile in save-only mode. Preserve unrelated role constraints;
prune only launch roles proven unused by immutable inputs or explicit step skips.
Use the existing surface-specific session capture through dependency injection.

## Validation and review gates

Use failing behavior tests before fixes: artifact validation/archiving, immutable packet,
non-Git/workspace roots, save-only profile admission, launch selection, self-initiated
briefing, and action failure/cancel boundaries. Run CLI build/smoke/unit/integration,
relevant App tests, make check, and make build-app.

Self-review plan coverage and unnecessary complexity before opening a non-draft PR.
Then request at least two adversarial review rounds from the neighboring Pi pane. Verify
findings, reproduce real issues, and add regression tests before fixes. Record each round
on the PR; continue while P0/P1 or major-UX P2 issues remain.

After the review gate, use an isolated Debug instance for actual Codex/Pi scenarios:
self-initiated and GUI starts, save-only, receiver continuation, and relevant failure
handling. Check the packet, receipt, run state, and receiver behavior. Finally reconcile
component/CLI documentation and the shipped workflow skill with the observed behavior.

## Implementation and self-review

The shipped bundle uses the existing delivery and launch steps. `WorkflowHandoffAction`
reuses `HandoffCoordinator.makeCheckpoint`; its receiver packet is built from the save's
own values rather than mutable shared files. The generic role requirement calculation is
shared by admission, machine startup, and the native start sheet. Runtime expressions keep
both branches eligible. No profile/runtime allow-list, new launcher, or legacy migration was
introduced.

Self-review checked the approved additive scope, first-step self-initiation, archive lifetime,
source-session capture, optional profile selection, and failure-before-write boundaries.
Focused tests cover Git/plain storage, preserved old briefings, immutable packets, rejected
external/invalid/symlink inputs, both admitted paths, and reducer session capture. Existing
HandoffStore tests cover workspace collection; existing runner tests cover cancellation.
The normal local `workflow validate` command treats files as user scope and correctly rejects
reserved IDs; the shipped bundle is tested with bundle-scope discovery instead.

Before PR: CLI build, smoke, unit (225 XCTest plus 69 Swift Testing), and integration
(112 tests) passed. The initial app core run passed 137 tests; focused follow-ups passed
25 and 53 tests. Bundle/role tests passed four tests. `make check` passed. External review
and live acceptance are tracked separately below when complete.
