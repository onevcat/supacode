# 030.012 — Claude Screen Profile: Action

> Amended by [014-claude-full-screen-live-block.md](014-claude-full-screen-live-block.md):
> Claude now consumes the full active screen and the live status region is bounded by
> row shape instead of `suffix(3)`; the canonical-tail contract and the Debug
> canonical-tail assert described below no longer apply to Claude.

> Amended by [016-claude-titled-composer-border.md](016-claude-titled-composer-border.md):
> the composer border may carry a session title chip; the idle composer rule and the
> live block anchor accept it.

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-08-07 |
| **Branch** | `feat/claude-screen-profile` |
| **PR** | #688 (stacked on #687) |
| **Plan** | [007-screen-profile-migration-plan.md](007-screen-profile-migration-plan.md), Phase 5 |

## Result

Claude state detection now runs through one runtime-owned typed Swift profile. The profile
constructs its live regions once from the canonical detector input and evaluates rules in
explicit source order:

1. transcript/history viewer → `unknown / claude.viewer`;
2. current numbered selection blocker → `blocked / claude.blockedPrompt`;
3. scoped live spinner row → `working / claude.spinner`;
4. complete elapsed-status token → `working / claude.elapsedStatus`;
5. below-prompt workflow footer → `working / claude.backgroundWork`;
6. bordered current composer → `idle / claude.idleComposer`;
7. no match → `idle / fallback.noRuleMatched`.

Viewer `.unknown` therefore still preserves the last trusted stabilized state; it never
forces idle. Blocked still outranks retained working chrome, spinner/elapsed rows remain
limited to the three recent non-empty lines above the current prompt box, and `agents done`
remains limited to the below-prompt footer. No subagent-wait rule was added because no
captured failing screen supports one.

`ClaudeScreenRegions` owns Claude viewer, current interaction, live status, below-prompt,
and composer boundaries. Shared mechanical predicates retain one owner while another
runtime still uses them. `AgentScreenSnapshot` now asserts its canonical-tail contract in
Debug before Phase 5 adds the second production profile caller.

## Capture-backed #676 fix

The fresh Claude 2.1.223 history-search capture uses current chrome:

```text
⌕ Filter history…
↑/↓ to nav · Enter to use · Esc to cancel · ctrl+s to scope
```

The legacy detector recognized only older `⌕ Search…` / `ctrl+r to toggle` forms and
returned idle. The profile requires the complete current filter/navigation/footer
structure and returns `.unknown / claude.viewer`. The unchanged detector-faithful capture
was promoted from executable quarantine to the normal `unknown` corpus path; its issue
metadata is now explicitly null. This is the migration's only intentional Claude state
difference and is backed by issue #676 plus captured provenance.

## Migration protocol

The migration used the same two-commit protocol as Codex:

- `87451326` added the non-production Claude profile, stable IDs, canonical snapshot guard,
  and temporary parity harness. All 22 existing inline Claude call sites stayed equal to
  the legacy detector; seven ordinary captures stayed equal, while the quarantined viewer
  explicitly proved the one intended `idle → unknown` difference.
- `a8549eb6` routed production to the profile, required every existing inline test to
  return a non-legacy reason, removed the temporary comparator and legacy Claude helpers,
  and promoted the viewer fixture.

At no point does a shipped production path run both Claude classifiers. The remaining 13
runtimes still use their unchanged legacy detectors and report `legacy.detector`.

## Behavior and ownership

The current-selection gate, quoted/stale negatives, old viewer forms, spinner glyph set,
elapsed token parser, background-work footer, canonical 24-line tail, exact cache identity,
3-second hold, polling, and display-state projection are unchanged. Positive idle composer
recognition changes only the reason; ordinary no-match remains idle.

Claude-exclusive parsing moved out of `ScreenHeuristics.swift` and the legacy detector was
removed. Recent-line extraction, numbered-choice parsing, generic confirmation vocabulary,
and the spinner glyph predicate remain shared because Codex or unmigrated runtimes still
call them.

## Validation

TDD and parity evidence:

- profile tests initially failed to compile because the Claude profile API did not exist;
- the non-production profile then passed all 22 inline parity call sites, seven ordinary
  fixture comparisons, and the explicit quarantined-viewer difference;
- production routing next failed in 14 test methods while production still emitted
  `legacy.detector`, then passed after the switch;
- focused profile, heuristic, corpus, result, and cache tests: 59 passed;
- full app suite: xcsift reported 2,290 passed; xcresult independently verified 2,292 tests
  and zero failures;
- `make check` passed;
- `make bench`: 6 passed. At `a8549eb6`, the complete 15-fixture corpus measured
  **2.522 ms median**, versus Phase 4's 2.960 ms (**-14.8%**). Region derivation remains a
  net win despite Claude's larger rule set.

The GUI session remained locked at `loginwindow`, so no new live CLI reason observation is
claimed. Current-version behavior is grounded in the detector-faithful Claude 2.1.223
captures from [009](009-captured-screen-fixture-corpus.md); retry live verification when
unlocked and on the final simulated-integration branch.

## Adoption gate

Stop profile migration after Claude and Codex. No third runtime currently has both fresh
capture provenance and demonstrated maintenance pressure, so further migration would be
ritual rather than evidence-driven. Keep the 13 legacy detectors as an accepted steady
state until a real drift report supplies both conditions.
