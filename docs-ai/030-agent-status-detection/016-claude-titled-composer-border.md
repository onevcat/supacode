# 016 — Claude composer border with a session title chip

Amends [012-claude-screen-profile.md](012-claude-screen-profile.md) and
[014-claude-full-screen-live-block.md](014-claude-full-screen-live-block.md): the composer
border that anchors both the live status block and the `claude.idleComposer` rule is no
longer required to be rule characters only.

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-09-09 |
| **Branch** | `fix/claude-titled-composer-border` |

## Problem

Claude Code paints a named session's title as a chip on the composer's top border:

```text
✢ Crafting… (19s · still thinking with xhigh effort)
  ⎿  Tip: Did you know you can drag and drop image files into your terminal?

──────────────────────────────────── Titled composer border probe ─
❯
────────────────────────────────────────────────────────────────────
```

The chip has existed for named sessions (`/rename`, `--name`, hook-set titles) since
2.1.129 and was realigned in 2.1.236; the reported 2.1.266 screen carried one with an
auto-generated-looking title. `isBoxBorderLine` accepted only lines made entirely of
`─`/`-`, so a titled border was not a border:

- `contentAbovePrompt` found no border and kept the titled row inside the region above
  the prompt.
- `liveStatusBlock` walked bottom-up, met that row first, and stopped: it is not live
  chrome and has no queued `❯` head above it. The live block was empty, so the spinner,
  elapsed-status, and background-work rules never saw the spinner row.
- `hasIdleComposer` failed for the same reason, so the screen fell through to
  `fallback.noRuleMatched` — idle — while the agent was working.

`prowl agents --json` on the live pane reported `idle / fallback.noRuleMatched` for both
the spinner screen and the empty composer.

## Fix

`isBoxBorderLine` now accepts a run of at least three rule characters followed by an
optional title chip: a space-led segment that ends with a rule character. A plain rule
line still matches. Nothing else in the profile changed; the shape-bounded live block and
the idle composer rule work as before once the border is recognized.

A false positive here costs little: `contentAbovePrompt` uses the *last* border above the
prompt, which is the composer's own, and `hasIdleComposer` only inspects the rows adjacent
to the prompt.

## Evidence

Two captures from a scripted probe session on Claude Code 2.1.266 (179×58), titled via
`/rename`, redacted with `scripts/make-detection-fixture.py`:

- `claude/2.1.266/working/titled-border-spinner.txt` → `working / claude.spinner`
- `claude/2.1.266/idle/titled-composer.txt` → `idle / claude.idleComposer`

Both failed against the previous detector (working read as idle; idle matched no rule)
and pass after the change.

## Non-goals

- Reading the title out of the chip. Tab titles already come from the terminal title.
- Treating chips on other rows as borders; only the composer frame is affected.
