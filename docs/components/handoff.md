# Handoff — Agent To Agent

> How to hand a task off between coding agents inside a Prowl runnable target:
> a pure, archive-first transition over `.prowl/handoff/`, an inline
> agent-authored briefing (`prowl handoff to <agent> --brief -`), a headless
> background launch of the receiver, and in-app entry points (Agents capsule,
> Hand Off HUD, command palette) that ask the live agent to run that same CLI
> transition itself.

**Keywords:** handoff, hand off, briefing, codex, claude, switch agent, takeover, `.prowl/handoff`, current.md, prowl handoff, --brief, cross-agent, workspace

**Related:** [workspaces](workspaces.md) · [cli](cli.md) · [agent-detection](agent-detection.md) · [command-palette](command-palette.md)

## Workflow entry point

The built-in `prowl.handoff` adds an agent-authored workflow entry point alongside the
existing HUD and commands described below. It asks the current agent for a briefing,
saves it with generated context, then launches a receiving Profile unless `next=save`.
The receiver reads an independent packet in `archive/workflow-<run UUID>.md`, so later
handoffs cannot replace its instructions. Workflow history cleanup does not delete these
handoff packets. See [Built-in Handoff](workflows.md#built-in-handoff) for commands and
completion semantics. The legacy transition sequence below is unchanged.

## Why

Coding agents are independent processes; each keeps its own conversation
context. When you switch from one to another, the first agent's in-memory
context is **not** visible to the second. The only durable channel between them
is the filesystem. Handoff makes that channel a first-class, structured
artifact — and makes sure the artifact is **fresh** for every transition: the
receiver never reads a previous round's notes as if they were today's
contract.

Handoff is centred on [workspaces](workspaces.md) — one task, several repos, a
shared root — but works for any runnable target.

## The transition

The legacy HUD and `prowl handoff` CLI share this transition sequence:

```text
collect briefing → archive outgoing state → install fresh current.md
(or remove the stale one) → regenerate context.md → launch receiver
(background tab) → log + notification
```

- The **archive comes first**: whatever the previous round left in
  `current.md`/`context.md` is snapshotted to
  `archive/<ts>-<from>-to-<to>.md` before anything is rewritten, so history
  always survives.
- `current.md` **exists iff a validated briefing produced it**. There is no
  template and no manual upkeep; when no briefing is available the file is
  removed and the receiver is pointed at `context.md` + `archive/` instead.
- `context.md` is derived at transition time from live git state and the
  pane's session identity — it is never "maintained" between handoffs.
- The launch is **headless**: the receiving agent starts in a background tab
  of the same worktree. Nothing switches your selected worktree, steals
  focus, or raises a window. A notification (`codex → claude · <worktree>`,
  click to jump) fires unless you are already watching that worktree — there,
  the appearing tab is the signal.

## The briefing: explicit input

The briefing is always **agent-authored** and supplied explicitly:

- **Inline (`--brief`) — the primary path.** The outgoing agent hands itself
  off as its final action and writes the briefing in the same breath:

  ```bash
  prowl handoff to codex --brief - <<'EOF'
  # Handoff
  ## Objective
  …
  ## Current State
  …
  ## What Has Been Done
  …
  ## Open Questions
  …
  ## Risks / Watch Out
  …
  ## Next Steps
  …
  ## Suggested Prompt For Next Agent
  …
  EOF
  ```

  The live agent holds working context that no recorded transcript can
  reproduce (on current models, transcripts persist reasoning as empty signed
  stubs), plus the *intent* of the handoff itself — which is exactly what
  "Suggested Prompt For Next Agent" needs. Inline costs no extra model call
  and no waiting.
- **Context-only.** With an explicit `--no-brief`, the
  transition carries `context.md` and the archive chain only.

Every command must choose one of those inputs; Prowl never resumes a recorded
session or starts a hidden model turn to synthesize a briefing. A briefing must
contain at least `## Objective`,
`## Current State`, and `## Next Steps` (chat preamble and code fences are
stripped). An invalid inline brief errors with guidance and **zero side effects**.

## The artifact

Everything lives under the target's `.prowl/handoff/` directory:

```text
<root>/.prowl/handoff/
  .gitignore            self-ignore all local handoff state
  current.md            the current validated briefing (absent when none)
  context.md            Prowl-generated repository and session state
  log.md                append-only handoff history
  archive/<ts>-<from>-to-<to>.md      outgoing snapshot of each transition
  archive/<ts>-replaced-current.md    briefing replaced by a checkpoint
  sessions/<ts>-<pane>.md             terminal excerpt per save
```

Prowl creates `.prowl/handoff/.gitignore` with `*`, so the entire directory is
self-ignoring when the target is a git repository or worktree.

`sessions/<ts>-<pane>.md` is a normalized excerpt from the outgoing pane. It
records the detected agent, session id, pane, source, confidence, and native
transcript path when one is available — the same pid-anchored session identity
exposed by `prowl agents`. Ambiguous sessions are omitted rather than guessed.

## The `prowl handoff` command

```bash
prowl handoff to <agent> [target] [--brief -|--no-brief] [--note "…"] [--no-launch]
prowl handoff save       [target] [--brief -|--no-brief] [--note "…"]
```

- **`to <agent>`** runs the full transition and launches the receiver in a
  background tab. Interactive launch is verified for `claude` and `codex`;
  `--no-launch` still archives + saves and accepts every detected-agent
  token (`pi`, `omp`, `claude`, `codex`, `gemini`, `cursor-agent`, `cline`,
  `opencode`, `copilot`, `kimi`, `droid`, `amp`, `qodercli`, `qwen`, `grok`).
- **`save`** is the deferred-handoff checkpoint: install a fresh briefing and
  regenerate context, with no destination and no launch. Use it when you stop
  for the day and the successor doesn't exist yet. A checkpoint never removes
  an earlier briefing — with no receiver, the last valid one stays.

### Who is the source?

- An explicit selector (`--pane p3`, `--tab t2`, `--worktree <name>`, or the
  positional target) always wins.
- Otherwise the source is **the calling pane**: Prowl resolves the `prowl`
  process's ancestry to the pane whose shell spawned it. An agent running
  `prowl handoff to …` inside its pane is therefore handing off **itself** —
  no matter what you have focused.
- Run outside any Prowl pane with no selector, the command errors
  (`SOURCE_REQUIRED`). The focused pane is never guessed at.

Every handoff requires `--brief` or an explicit `--no-brief`, including commands
that target another pane. A missing choice errors with a copy-pasteable heredoc
and zero side effects; Prowl never makes an implicit paid model call on behalf
of a third-party caller.

The receiving agent's kickoff prompt adapts: with a briefing it starts from
`current.md`'s Next Steps; without one it orients from `context.md` and the
archive. When Prowl observed the outgoing launch, an explicitly observed
unrestricted execution mode carries over to the **destination launch only**
across the verified claude/codex adapters; model identifiers stay within the
same agent family. Full flag/payload reference: [cli](cli.md#prowl-handoff).

## In the app: the Agents capsule and the Hand Off HUD

A capsule button leads the top toolbar and identifies the selected pane's
detected agent; the notifications bell follows it in every view mode. Clicking
it opens a popover whose hand-off row explains the action — "Pass this task to
another agent in a new tab; <agent> writes its own
briefing first" — and opens a centered HUD. The popover is always available.
When a worktree/card is focused, it lists launchable
[agent profiles](agent-profiles.md) (Recommended first) below the hand-off row,
even when no agent is detected. With no focused Canvas card, launch rows and
Quick Launch are omitted because they have no destination; **Manage Agent
Profiles…** remains available. The Command Palette (`⌘P`) offers
the same flow as a single **Hand Off…** row; so does right-clicking a row in
the [Active Agents panel](active-agents.md), which targets the row's own pane.

The HUD is a trigger and an observer for the same CLI transition:

1. **Choose** — pick the receiving agent (the current agent stays listed as a
   fresh-session restart) or **Only save progress, don't hand off**.
2. **Ask the live agent** — Prowl types a one-line request into the source
   pane asking the agent to run `prowl handoff … --brief -` itself, then
   waits. The agent writes its briefing in its own words and the transition
   completes through the CLI service; the HUD observes the completion and
   jumps you to the receiver. If the agent is busy, the request queues in its
   input — the HUD says so. While waiting the panel is **non-modal**: the
   keyboard stays with the terminal (the request may trigger permission
   prompts you need to approve), and clicking outside collapses the panel —
   the hand-off still completes headlessly and notifies.
3. **Fallback while waiting** — **Context Only** hands off without a briefing;
   **Cancel** closes the panel (an already-injected request can't be unsent —
   if the agent still hands off, it completes headlessly and notifies). If the
   request cannot be delivered to the source pane, Prowl takes the context-only
   path automatically.

Because the request is plain language, **any detected agent can be a
source** — the pane-injection path is not limited to claude/codex.

## Safety

- Handoff never commits, pushes, or runs destructive git — saving only
  **reads** git state (`status` / `diff --stat`).
- Unrestricted-mode inheritance applies only to the interactive destination
  launch; briefing collection never starts another agent process.
- Archive-before-write is a global invariant: no rewrite of `current.md` can
  destroy the only copy of the previous round.
- `to` only **adds** a background tab; it never closes the outgoing agent's
  session, so you can still read or roll back from it.
- Keep secrets/tokens out of the briefing; `.prowl/handoff/` is self-ignoring
  and session excerpts belong in local state, not source control.

## Gotchas

- Workspaces aggregate generated context across their child repositories. A
  regular repository or worktree covers just that repo; a plain folder omits
  git branch and diff details.
- The HUD's injected request lands in the agent's input queue; a busy agent
  answers it after its current step. Use **Context Only** if you cannot wait —
  or Cancel, and the handoff completes in the background
  when the agent gets to it.
- Launching uses the interactive receiving agent (so you can step in); don't
  use `--capture` against it — read its screen with `prowl read --wait-stable`.
