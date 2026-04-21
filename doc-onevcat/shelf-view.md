# Shelf View

Last updated: 2026-04-21
Status: Implemented (see **Implementation Decisions Journal** at the bottom for deviations taken during implementation)

A new terminal presentation mode that sits alongside Canvas. Where Canvas spreads
worktrees out as flat cards and weakens the worktree concept, Shelf preserves and
strengthens it: each worktree (or plain folder) becomes a "book" with a vertical
spine that doubles as its tab bar. Exactly one book is "open" at any time,
occupying the space between a left stack of already-passed spines and a right
stack of upcoming spines.

---

## Mode & Entry Point

- Shelf is a terminal-region presentation mode, **mutually exclusive** with
  Canvas. The left navigation remains visible in Shelf mode (Shelf only occupies
  the terminal region to the right of the navigation).
- The Shelf toggle lives next to the Canvas toggle in the same toolbar `HStack`,
  placed immediately to the **right of** (i.e. after) the Canvas entry.
- Toggle hotkey: **`Cmd+Shift+Enter`** — symmetric with `Toggle Canvas`'s
  `Cmd+Option+Enter`.
- **Exit Shelf**: only by re-clicking the Shelf toggle (or pressing the toggle
  hotkey). Clicking a different worktree in the left navigation does **not**
  exit Shelf — it merely changes which book is open. (This differs from Canvas,
  where left-nav clicks exit the mode, because Canvas weakens the worktree
  concept while Shelf treats `book = worktree` 1:1.)

---

## Concept Mapping

| Shelf concept | Prowl model |
|---|---|
| Book | A worktree or a plain folder |
| Spine | The book's vertical tab bar; also carries its identity (worktree/folder name + branch) |
| Open book body | The terminal surface (with splits) of the book's currently active tab |

**Order of books on the shelf** equals the order of worktrees / plain folders in
the left navigation. Reordering happens through the left nav, not on the shelf.

---

## Layout Invariant

The terminal region (everything to the right of the left navigation) is split
into three horizontal segments:

```
[ left spine stack ] [ open book terminal area ] [ right spine stack ]
```

Let `N` be the index of the currently open book among all books `1…last`:

- **Left stack** = spines of books `1…N`, in book order. Book `N`'s spine is the
  rightmost in the left stack and sits flush against the left edge of the
  terminal area.
- **Terminal area** = the surface of book `N`'s currently active tab (with the
  existing split logic).
- **Right stack** = spines of books `N+1…last`, in book order, flush against
  the window's right edge.

**Initial state on entering Shelf**: `N` is the worktree currently identified by
`WorktreeTerminalManager.selectedWorktreeID`; the open book's active tab is
that worktree's currently active tab (no separate Shelf-only tab memory).

**Book set = opened worktrees/folders only**: the spines shown on the Shelf
are *not* the full list of worktrees + plain folders in the sidebar. The
Shelf only includes books the user has interacted with at least once in
the current session — i.e., those with an associated terminal state. A
worktree that appears in the left navigation but has never been clicked (or
touched by CLI / layout restore) does *not* get a spine. Clicking an
as-yet-unopened worktree in the left navigation while Shelf is active is
what makes its spine materialize — the normal spine-flow animation applies
as the new spine slides into its sidebar-order position.

---

## Spine Specification

### Geometry

- **Width**: one line of text (compact, fixed across all spines and across
  open/closed states).
- **Identical structure and width whether the book is open or closed**; only
  the area to the spine's right changes (terminal surface vs. nothing).

### Header (top of spine)

- Worktree name + branch name, rendered **rotated 90°** (vertical reading
  direction).
- For **plain folders** (no branch): only the folder name is shown, with the
  branch line entirely omitted (consistent with how plain folders are presented
  in the left navigation today).
- The header is **not** part of the scrollable area (see Tab List Overflow).

### Tab List (below header)

- Each tab is rendered as **its icon only** (Prowl already supports per-tab
  custom icons). No label text in the slot.
- Each slot is a uniform-sized clickable target.
- **Hotkey overlay**: when the user holds **⌘ (Command)**, the icon in each
  slot is **replaced** by the tab's `Cmd+N` digit (1–9). Slot size and position
  do not change — there is zero layout shift. This matches Prowl's existing
  "hold ⌘ to reveal hotkeys" behavior.
- For tabs at index ≥ 10 (no `Cmd+N` hotkey): when ⌘ is held, the slot continues
  to show the icon (optionally slightly dimmed to hint "no hotkey"); details left
  to implementation.

### Tab List Overflow

- When the tab list does not fit the available spine height, the **tab list
  area scrolls vertically**.
- The header (worktree/branch) stays **pinned** and does not scroll.
- The bottom controls (see below) also stay pinned and do not scroll.

### Bottom Controls

- A row of three buttons at the spine's bottom: **`+` / vertical split /
  horizontal split**, mirroring Prowl's standard tab bar.
- These controls are **only shown on the spine of the currently open book**.
  Closed-book spines do not show them (acting on a non-open book first requires
  opening it).

### Per-Tab Visual States (must all be respected, simultaneously when applicable)

- **Active tab highlight** — the book's currently selected tab.
- **Notification highlight** — drives off the existing
  `WorktreeTerminalState.hasUnseenNotification(for:)`. Visual: **slot
  background tint**, using the same color/style as Canvas title-bar
  notification highlights (reuse the existing token / style for consistency).

### Book-Level Aggregated Notification

- When **any** tab in a book has an unread notification, a **small dot badge**
  is shown on the spine **header** (next to the worktree/branch text).
- Purpose: when a notifying tab is scrolled out of view in the spine's tab
  list, the user can still see at a glance "this book has activity".
- No directional arrow / no "scroll up to see" hint — keep it minimal.

---

## Open Book Visual Distinction

The open book's spine is visually distinguished from other spines through a
**combination** of:

- An **accent color / contrasting background tint** on the open book's spine,
  and
- **Visual continuity** with the terminal area: the spine and terminal area
  share background color and/or border treatment so the spine reads as "the
  left edge of the open page" — reinforcing the book metaphor.

(Active-tab highlight on the spine's currently-active tab slot is a separate,
**tab-level** signal, independent of the **book-level** open-book signal.
Both can be visible at once.)

---

## Interaction

### Book ↔ Left Navigation Sync (bidirectional)

- **Shelf → Left nav**: clicking a different spine in Shelf updates
  `selectedWorktreeID` (and therefore the left-nav selection).
- **Left nav → Shelf**: while in Shelf mode, clicking a worktree in the left
  navigation triggers the same spine-flow animation as clicking that book's
  spine directly. The Shelf does not exit.

The single source of truth for "which book is open" is `selectedWorktreeID`.

### Switching Books (clicking a non-open book's spine)

Clicking spine `M` (where `M ≠ N`):

- If the click lands on a specific tab slot `T` on spine `M`: animate the
  spine flow (rules below), open book `M`, and set `M`'s active tab to `T`.
- If the click lands on the spine **header** only: animate the spine flow,
  open book `M`, keep `M`'s previously active tab.

**Spine flow rules:**

- **`M > N` (forward)**: spines `N+1…M` slide from the right stack into the
  tail of the left stack. Spines `M+1…last` do not move.
- **`M < N` (backward)**: spines `M+1…N` slide from the left stack back to the
  head of the right stack. Spines `1…M-1` do not move.

In both cases the previously open book's spine ends up wherever the flow
places it (no special case).

### Switching Tabs Within the Open Book

Clicking a tab slot on the **currently open** book's own spine:

- **No spine animation, no page-turn transition.** The spine layout is
  unchanged.
- The terminal area is replaced with the newly selected tab's surface.

### Unified Click Rule

Every tab slot on every spine is a click target meaning "switch to this book
and this tab". Whether the click triggers spine-flow animation depends solely
on whether the targeted book is already the open book.

### Creating Tabs / Splits

- Use the **bottom controls** (`+` / vsplit / hsplit) on the **open book's**
  spine, or the existing keyboard shortcuts.
- To add a tab to a non-open book: open it first by clicking its spine, then
  use the bottom controls.

### Closing Tabs

Mirror Prowl's normal-mode tab close behavior:

- **Hover X**: hovering a tab slot reveals a small X button to close it.
- **Right-click menu**: right-clicking a tab slot opens a tab-level context
  menu containing Close (and any other existing tab actions).
- **`Cmd+W`** keyboard shortcut continues to close the active tab.

### Closing the Last Tab in a Book

Closing the last tab does **not** remove the book from the shelf. Instead, the
book remains, its spine stays in place, and the open area shows an **empty
terminal placeholder UI** (consistent with normal-mode behavior). The user can
add a tab back via the bottom controls (after opening the book).

### Removing a Book from the Shelf

A book is removed from the shelf only by:

1. **Closing/removing the worktree** through the left navigation (existing
   pathway), or
2. **Right-clicking the spine header** → context menu → **"Remove book"**.

Right-click scoping:

- Right-click on a **tab slot** → tab-level context menu (Close, etc.).
- Right-click on the **spine header or its empty body area** → book-level
  context menu (Remove book, etc.).

---

## Animation Specification

### Axis 1 — Spine flow character

- **Snappy**: ~200ms, ease-in-out. Crisp, minimal hang time.

### Axis 2 — Terminal area swap

- Use SwiftUI **`matchedGeometryEffect`** (or the closest equivalent): the
  terminal area is treated as a piece of "openable book content" that
  geometrically transforms together with its spine.
- During transitions, **two terminals may coexist briefly** in the terminal
  region:
  - **Forward (`M > N`, "pulling in")**: book `M`'s terminal slides in from
    the right alongside `M`'s spine. The previously open book `N`'s terminal
    stays in place and **fades out** as `M`'s terminal arrives, so the user
    never sees a half-clipped or partially-replaced surface.
  - **Backward (`M < N`, "pushing out")**: book `N`'s terminal slides out to
    the right alongside `N`'s spine and **fades out** during the slide. Book
    `M`'s terminal materializes at its destination (slide-in or fade-in, as
    looks best in implementation).
- **Unified rule**: the "about to be invisible" terminal handles the fade; the
  "about to be visible" terminal stays opaque (slide-in) or fades in. This
  prevents surface views from popping in / out abruptly and avoids visual
  tears against the moving spines.

---

## Keyboard Shortcuts

All Shelf-related shortcuts are **configurable** through Prowl's existing
keybinding system (`scope = configurableAppAction`), exposed in
`Settings → Shortcuts`.

| Command | Default binding | Notes |
|---|---|---|
| `toggleShelf` | `Cmd+Shift+Enter` | New command. Symmetric with `toggleCanvas` (`Cmd+Option+Enter`). |
| `selectTerminalTab1…9` | `Cmd+1..9` | **Existing** commands. In Shelf, they switch tabs within the open book. |
| `selectPreviousTerminalTab` / `selectNextTerminalTab` | `Cmd+Shift+[` / `Cmd+Shift+]` | **Existing** — apply within the open book. |
| `selectNextWorktree` / `selectPreviousWorktree` | Unchanged: `Cmd+Ctrl+↓` / `Cmd+Ctrl+↑` | Unchanged. See `selectNext/PreviousShelfBook` below for the `Cmd+Ctrl+→` / `Cmd+Ctrl+←` bindings on the Shelf. |
| `selectNextShelfBook` / `selectPreviousShelfBook` | `Cmd+Ctrl+→` / `Cmd+Ctrl+←` | **New commands**. Operate on the ordered Shelf-book list (worktrees + plain folders), which can diverge from the worktree list if plain folders are interleaved. See the Implementation Decisions Journal for why we took this over a two-binding alias on the worktree commands. |
| `selectShelfBook1…9` | `Ctrl+Option+1..9` | **New commands**, deliberately distinct from `selectWorktree1..9` (`Ctrl+1..9`). Books and worktrees are not 1:1 in numbering: "books on the shelf" can diverge from "items in the left navigation" (e.g. presence/absence on the shelf, plain-folder ordering). Shelf-specific. |

### Implementation note on multi-binding

The current `KeybindingSchema` / `AppShortcut` / `Binding` model holds a single
`shortcut` per command. The `Cmd+Ctrl+←/→` alias for
`selectNext/PreviousWorktree` requires a non-trivial extension to support a
collection of bindings per command (and to surface that in the settings UI).
If this cost proves prohibitive, the fallback is to introduce wrapper commands
(e.g. `selectNextBookAlias`) that invoke the same underlying action, at the
cost of duplicating rows in the shortcuts settings list.

---

## Mapping to Existing Models

- The ordered list of spines mirrors the ordered list of worktrees + plain
  folders tracked by `WorktreeTerminalManager`.
- Each spine's tab list mirrors that worktree's `TerminalTabManager` tabs.
- The terminal area renders the active tab's `GhosttySurfaceState` (and any
  splits) using the existing surface-rendering path.
- `WorktreeTerminalManager.selectedWorktreeID` ↔ "the open book", driven by
  spine clicks and left-nav clicks alike (single source of truth).
- Per-spine tab-slot notification highlights consume
  `WorktreeTerminalState.hasUnseenNotification(for:)`.
- Per-book aggregated header dot consumes
  `WorktreeTerminalState.hasUnseenNotification` (book-wide).

---

## Open Implementation Questions (non-blocking)

- Spine height budget per slot, and the exact dimming treatment for tabs ≥ 10
  when ⌘ is held.
- Exact accent color / continuity treatment for the open book's spine + terminal
  area (decide during visual implementation; iterate if it looks off).
- Whether the spine should auto-scroll to reveal a newly-arriving notification
  (vs. relying solely on the aggregated header dot).
- Multi-binding architectural change (see Keyboard Shortcuts → Implementation
  note) — design before implementation.
- Empty-state visuals for an empty Shelf (no books at all).
- Animation behavior under user interruption (e.g. clicking a third spine while
  a transition is mid-flight).

---

## Implementation Decisions Journal

Decisions made during implementation that deviate from — or add nuance to —
the earlier design, recorded for review.

### Keyboard Shortcuts: wrapper commands over multi-binding

**Design spec** had `Cmd+Ctrl+→` / `Cmd+Ctrl+←` as a second alias on the
existing `selectNext/PreviousWorktree` commands, with a note that this
requires a non-trivial extension to the keybinding schema (singular
`shortcut` → collection).

**Implemented** as distinct `selectNextShelfBook` / `selectPreviousShelfBook`
commands. Reasons:

- The Shelf-book ordering includes plain folders (interleaved per
  `orderedShelfBooks()`), so "next book on the Shelf" is not semantically
  equal to "next worktree" when plain folders exist. Aliasing would have
  skipped plain folders when a user pressed the arrow alias.
- The wrapper-command approach keeps `AppShortcut.Binding.shortcut` singular,
  avoiding the schema change.
- Both commands still live in `Settings → Shortcuts` so users can remap
  either set independently.

### Commands plumbing: merged into `SidebarCommands`

Originally planned as a separate `ShelfCommands: Commands` struct. Moved into
`SidebarCommands` because SwiftUI's `@CommandsBuilder` caps the number of
direct children in a `.commands { }` block; adding a new top-level Commands
struct pushed the builder past the cap and triggered a compile error on
unrelated `CommandGroup`s. Merging keeps the external menu footprint the
same (two visible toggles + one Worktrees menu).

### `isShelfActive` as a separate flag

`RepositoriesFeature.State` gained a new `isShelfActive: Bool` flag instead
of adding a `.shelf` case to `SidebarSelection`. Reason: Shelf is a
presentation mode that still needs `selection` to track a worktree or plain
folder (the open book). Using a dedicated flag decouples "is Shelf active"
from "which book is open", which lets the bidirectional sync with the left
navigation fall out for free.

### Auto-exit rules

Entering Canvas or Archived Worktrees from any entry point clears
`isShelfActive` — those two presentation modes are mutually exclusive with
Shelf by design. Entering Shelf from Canvas / archived redirects selection
to a compatible worktree / plain-folder before flipping the flag.

### Terminal rendering in the open area

Rather than reusing `WorktreeTerminalTabsView` (which includes the horizontal
tab bar), we introduced `ShelfOpenBookView` — a leaner view that renders only
the terminal content stack + icon picker sheet + window focus observer. In
Shelf, the tab bar lives on the spine, so duplicating it would violate the
design.

### Plain folder spines

`ShelfBook` uses `Worktree.ID` as its identity. For plain folders this is
the repository ID, matching the synthetic worktree emitted by
`RepositoriesFeature.State.selectedTerminalWorktree`. That way
`openShelfBookID == selectedTerminalWorktree?.id` for both kinds without
special-casing.

### Animation: `.animation(value:)` for both entry points

To make left-nav-originated book switches animate identically to
Shelf-originated taps, the root `HStack` carries an explicit
`.animation(.easeInOut(duration: 0.2), value: openBookID)` modifier.
Shelf-originated taps additionally pass the same animation to
`store.send(_, animation:)` so the TCA-side mutation carries the transaction
along.

### Close-last-tab behavior

The empty-book state falls out naturally: `ShelfOpenBookView` already
renders `EmptyTerminalPaneView(message: "No terminals open")` when
`selectedTabId == nil`. The spine remains on the shelf, with its bottom
controls still enabling new tab / split to recover.

### Opened-worktrees set

`RepositoriesFeature.State.openedWorktreeIDs: Set<Worktree.ID>` tracks
which worktrees/plain folders are currently part of the Shelf's book list.
It's updated by the reducer in four places:

- `.selectWorktree(id, _)` handler inserts `id` (covers sidebar click,
  Shelf click, most CLI opens, layout restore of the *active* worktree)
- `.selectRepository(id)` handler inserts `id` when the repository is a
  plain folder
- `.toggleShelf` entry path inserts the currently selected ID when the
  selection is already compatible with Shelf (rare path, but guards
  against state set without going through the two actions above)
- `.markWorktreeOpened(id)` — a dedicated action that AppFeature
  dispatches in response to `.terminalEvent(.tabCreated(worktreeID:))`.
  This is the *critical* catch-all for every path that sets
  `state.selection` directly without going through `.selectWorktree` —
  in particular, the cold-launch auto-selection that restores the last
  focused worktree (`state.selection = state.lastFocusedWorktreeID…` in
  `applyRepositories`) and the "first available after reload" fallback.
  Layout restore is a third such path. The common downstream signal in
  all of them is that the newly-focused worktree ends up materializing
  its first tab, emitting `.tabCreated`, which this forwarder converts
  into an `openedWorktreeIDs` insertion.

`orderedShelfBooks()` filters against this set. The set is pure
additive in this iteration — archived / removed worktrees still drop off
the Shelf because the book iteration is anchored on the live
`repositories` array, not on `openedWorktreeIDs`. That leaves a handful
of stale IDs in the set but no visible spines; pruning can be layered in
later if the set grows unbounded.
