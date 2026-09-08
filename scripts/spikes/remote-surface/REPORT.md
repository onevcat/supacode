# Local remote-surface feasibility spike

Date: 2026-09-09

## Result

**A fixed-size live Ghostty surface can be mirrored into another native Ghostty surface, with input returned to the original PTY.** The client can attach after output exists, disconnect, and reconnect without restarting the host process.

This was verified with running native windows and a deterministic interactive PTY fixture. It was not verified with a coding agent, a remote machine, or an iPhone. Both native surfaces share one harness process and Ghostty app runtime; the client relay is a separate child process and the display data crosses a real Unix socket. This does not prove separate native app processes or daemon ownership.

The result supports a narrow next phase. It does **not** establish that the current VT formatter is a complete terminal synchronization protocol.

## Revisions and isolation

- Prowl base: `d777383e` (`origin/main` when the work started).
- Ghostty pin: `a0671ce9b`.
- Branch: `spike/remote-surface`.
- Worktree: `/Users/onevcat/.prowl/repos/Prowl/remote-surface-spike`.
- The original checkout had unrelated changes on `feat/workflow-step-history`. No files there were edited by this spike.
- Production Prowl source and the Ghostty submodule revision are unchanged. The experimental Ghostty changes are retained as [a patch](ghostty-snapshot.patch), not a submodule revision update.

## Running path

```text
Host native Ghostty surface
  └─ shell / Python fixture / PTY
          ↓ terminal parser
     authoritative Ghostty terminal state
          ↓ snapshot under renderer-state mutex
     existing TerminalFormatter (.vt), active screen only
          ↓ owned byte buffer through a spike-only C function
     length-prefixed Unix socket frames
          ↓
Client Python relay (child of another native Ghostty surface)
          ↓ writes snapshots to its own PTY stdout
Client Ghostty parser → native Metal display

Client key event → Ghostty input encoder → relay PTY stdin
  → Unix socket → Host raw text binding → original Host PTY
```

The socket belongs to the harness and is restricted to mode `0600`. It provides no network authentication. The local test sends full snapshots, not PTY output history or cell patches.

The helper PTY is a way to feed output into the existing native surface without adding a new Ghostty IO backend. It is a spike adapter, not a proposed production session architecture.

## Implementation scope

The Ghostty change adds one experimental C export, `ghostty_surface_spike_snapshot`, and its header declaration. The implementation is 35 added Zig lines and reuses `TerminalFormatter`; it does not modify PTY ownership, the parser, or the renderer.

The exporter:

1. Locks the existing renderer-state mutex.
2. Selects the active screen at its current dimensions.
3. Serializes VT content, palette, styles, modes, and cursor position.
4. Returns an owned buffer released with the existing `ghostty_surface_free_text` API.

The harness is an independent AppKit executable in [main.m](main.m), with [fixture.py](fixture.py) and [relay.py](relay.py). No Prowl CLI or workflow endpoint was added. The scripted fixture has RGB colors, inverse and underline attributes, CJK text, combining characters, an emoji, an OSC 8 link, a positioned cursor, and primary/alternate screen switching.

## Observed checks

The final automated run used an 81-column, 25-row grid. [verify.py](verify.py) checks the saved evidence independently of the harness implementation.

| Check | Actual result |
| --- | --- |
| Late attach | Host runs first; client starts two seconds later and displays the existing screen. |
| Initial content | Host and client text dumps match exactly. |
| Styled round trip | Host VT snapshot equals the client's re-exported VT snapshot at every checkpoint. |
| Unicode | CJK, combining text, and emoji survive the round trip. |
| Cursor position | Client re-export includes row 9, column 5, matching Host. |
| Input | A client key increments the original fixture from count 0 to count 1. |
| Disconnect | Client surface and its connection are removed; Host increments to count 2 while detached. |
| Reconnect | A fresh client surface receives count 2 without a host restart. |
| Screen switch | Client keys switch Host to primary and back to alternate; both replicas match. |
| Input encoding | The received input stream is exactly `jpa`, with no extra paste wrappers. |
| Process continuity | Host child PID remains 13247; fixture PID remains 13248 across all captures. |
| Native appearance | The client window visibly shows the colored fixture. See [screenshot](evidence/client.jpg). |
| Repository checks | `make check` passed, including 152 script tests and workflow naming checks. |
| Baseline app build | `make build-app` passed with 0 errors and 0 warnings. This uses the pinned production framework, not the experimental framework. |

Five checkpoints are retained: `initial`, `input`, `reconnect`, `primary`, and `alternate-again`. Each has Host and Client text and VT captures under [evidence](evidence). Exact VT equality only covers fields that the formatter emits; it does not prove omitted state is preserved.

## Issues found during the experiment

### Continuous redraw flicker

The first version cleared and repainted the client every 200 ms, including unchanged content. The user observed continuous flicker in the native client window.

The final version compares snapshots before transmission and wraps each repaint in synchronized-output sequences (`CSI ? 2026 h/l`). Across the final 18-second scenario it sent only **5 frames / 29,495 payload bytes**, rather than repainting on every sample. Thus a static screen no longer receives periodic full redraws. The final native screenshot confirms the displayed content, but a still image is not a temporal flicker measurement. Rapidly changing output still needs separate validation; this is not a cell-diff implementation.

Polling and serialization remain at 5 Hz. Eliminating unchanged transmissions does not eliminate host snapshot work.

### Full formatter extras move the replay cursor

With `TerminalFormatter.extra = .all`, the source snapshot contained cursor position `9;5`, but the client ended at `9;73`. The formatter sets tab stops after restoring the cursor and leaves the cursor at the final tab-stop column.

The spike excludes unrelated full-checkpoint extras and retains styles, modes, and cursor position. The final round trip matches. This is a display-specific workaround, not a general fix to terminal checkpoint serialization.

### A text callback is not raw input

`ghostty_surface_text` calls Ghostty's clipboard-paste path. Using it for encoded input produced 39 bytes for three intended keys because the client added bracketed-paste wrappers. Feeding those bytes through the host paste API would apply paste semantics again.

The final harness uses key events on the client. On the host it uses the existing `text:` binding with each byte hex-escaped; that binding writes bytes directly to terminal IO. The retained input capture is exactly `jpa`.

Production code must distinguish key events, paste requests, already-encoded PTY input, and terminal-generated responses. The three-key fixture does not prove IME, modifiers, mouse input, or keyboard-protocol correctness.

### Snapshot fidelity is incomplete

- Completed OSC 8 links are omitted from VT content in this Ghostty revision. The visible word `Link` survives, but its URI does not. The formatter currently emits cell hyperlinks for HTML, not VT. The verification script records this known limitation explicitly.
- The fixture requests a blinking-bar cursor. The formatter preserves its position but does not emit its requested shape. Cursor shape and blink phase are not established by this spike.
- Only the current active screen is exported. Scrollback and the inactive screen are not restored as independent client state.
- Graphics, selection, scrolling, resize, margins/origin-mode interactions, alternate-screen history, wide characters at the last column, and sustained high-output TUIs were not tested.
- Modes are replayed into a real client terminal. This can enable terminal side effects. Clipboard callbacks are disabled in the harness. Production must define which modes/events are display state and which require host authority or client consent.

### Build environment

Zig 0.15.2 failed to link its build runner with the default Xcode 26.6 environment. Selecting Xcode 26.3 resolved the build issue. The first successful attempt also set an older SDK explicitly; the final reproducible build needs only:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
```

The final patched native XCFramework and harness both built successfully. An intermediate duplicate XCFramework packaging invocation collided; the serialized rebuild passed. The system-wide Xcode selection was not changed.

## Measurements and their limits

From [results.json](evidence/results.json):

- 79 exporter calls, including calls used to save evidence.
- Mean export duration: approximately 0.047 ms; maximum: approximately 0.134 ms.
- 5 transmitted full frames; approximately 5.9 KB per frame, mostly including palette data.

These are incidental measurements from a small synthetic screen, not a performance benchmark or production latency claim. They exclude client parsing, rendering, network delay, and multi-pane contention. Formatting currently holds the same mutex used by terminal/render state. A production implementation should copy only the required state while locked and encode outside the lock where possible.

## Expected production changes

| Area | Minimal mirror path | Larger runtime path |
| --- | --- | --- |
| Ghostty export | Stable display snapshot with dimensions, cursor metadata and explicit fidelity; complete frames plus revisions/patches. | A headless terminal state owned independently of native views. |
| Client rendering | Keep native rendering; replace helper-process ingress with a supported output source or custom renderer. | Native local and remote clients consume the same session protocol. |
| Input | Define raw input versus semantic key/paste events; handle terminal responses once. | Central input authority with per-client capabilities and control ownership. |
| Prowl integration | Map stable pane IDs to display subscriptions and commands. Keep client selection/layout independent. | Move PTY/process/session lifetime out of `GhosttySurfaceView` and into a runtime service. |
| Transport | Snapshot baseline, revision validation, bounded queues, backpressure, reconnect/resync. | Reuse the same session protocol through local IPC and SSH stdio. |
| Lifecycle | Host Prowl stays open; losing a client must not close Host panes. | Dedicated process if sessions must survive Prowl termination or updates. |
| Mobile | Fixed host grid is initially possible; mobile UI controls presentation. | Define resize authority, history access, keyboard/IME, graphics, clipboard and file transfer. |

The narrow export change was small. A reliable remote-terminal feature is not a one-function change: fidelity, event ownership, backpressure, and client ingress remain material work. The current native backend still owns an exec/PTY; this spike does not make it a render-only backend.

## Recommendation

Proceed with a second bounded experiment before committing to a daemon migration:

1. Define a per-pane display contract with a full snapshot, cursor shape/visibility, size, boot identity, and revision.
2. Compare a structured cell snapshot with a corrected VT display snapshot on the same recorded TUI cases. Include OSC 8, wrapping, scrolling, graphics policy, and mode changes.
3. Add dirty-driven updates and incremental patches, plus forced resync after an intentionally dropped update. Test sustained output for visible flicker and main-thread contention.
4. Run the host and native client as separate processes. Keep input and clipboard semantics explicit.

This directly tests the uncertain boundaries. SSH transport and workspace UI can follow after that contract works. Extracting a daemon can remain a separate decision if the initial requirement is only to attach while Host Prowl stays running.

## Reproduce

Use an isolated checkout at the recorded Prowl base, with its pinned Ghostty submodule initialized. Run on Apple Silicon macOS with a graphical login session, Xcode 26.3, mise/Zig 0.15.2, and Python 3 available. Build dependencies may need network access.

```bash
git submodule update --init --recursive ThirdParty/ghostty
scripts/spikes/remote-surface/build.sh /tmp/prowl-remote-spike-build
scripts/spikes/remote-surface/run.sh /tmp/prowl-remote-spike-build
```

`build.sh` applies the retained patch only if it applies cleanly, or recognizes it as already applied. It leaves those experimental submodule edits in the isolated checkout. It does not replace Prowl's production framework.

`run.sh` creates a fresh evidence directory by default and exits after the approximately 18-second scripted scenario. The scheduled checkpoints are a native integration harness; on a slow or suspended desktop a missed checkpoint causes verification to fail. `SPIKE_HOLD=1` delays the final capture and exit to five minutes for screenshots or interactive inspection. The normal timed checks run before that hold.

To verify the retained run without launching anything:

```bash
python3 scripts/spikes/remote-surface/verify.py scripts/spikes/remote-surface/evidence
```

The experiment launches only its synthetic Python fixture and display relay. It does not attach to or type into any existing user terminal or agent session.
