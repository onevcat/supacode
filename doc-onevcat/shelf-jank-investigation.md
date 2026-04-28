# Shelf Book-Switch Jank Investigation

Last updated: 2026-04-28
Status: Closed for now — landed P0/P1 wins, no further structural change planned. Long-term signposts retained for future regressions.

## Summary

When switching books quickly on the Shelf, the app showed visible jank: dropped frames, occasional multi-second main-thread blocks, and a sluggish feel. After ~9 traces and four code commits we landed two real fixes that eliminated the worst behaviour (Severe Hangs caused by an observability storm) and confirmed that the residual ~250 ms-per-click cost is rooted in SwiftUI animation/layout work that we cannot reduce without giving up the spine-flow animation entirely.

Final shipped state:

- `RepositorySectionView` no longer subscribes to `WorktreeTerminalManager.states` — body invocations dropped from ~7400/sec to ~850/sec under the same workload.
- `orderedShelfBooks()` no longer rebuilds a `Dictionary` and a stack of `Set`s on every `ShelfView.body` call.
- The redundant TCA-action animation transaction on Shelf-originated book switches was removed; the view-level `.animation(value: openBookID)` continues to drive the spine flow.
- A long-term `OSSignposter` toolkit on `SupaLogger` plus a small set of body / lifecycle / NSView-representable signposts make future regressions much easier to localize on the Points of Interest timeline.

What we tried but rolled back:

- Removing `.id(worktree.id)` from `ShelfOpenBookView` (Phase 2). Behaved as designed (subtree no longer rebuilt) but produced no measurable hitch reduction; reverted to keep the codebase smaller and to preserve `.transition(.opacity)`.
- Disabling the spine-flow animation entirely. Felt smooth in hand but did not actually reduce per-click work — it only removed the visual artefact. Reverted because the UX trade-off is not worth a perceptual-only win.

## Problem

Quickly clicking between books on the Shelf produced obvious frame drops. Initial Instruments capture (Animation Hitches template, Debug build) showed the situation was severe:

- 1 Severe Hang (2.02 s) plus 11 Hangs of 600–1000 ms each
- Main thread blocked for ~10.5 s out of a 25 s recording (~41 %)
- 460 234 SwiftUI updates in 25 s — i.e. ~18 000 view updates per second under steady fast-clicking

These numbers said the issue was not "one slow function" but a runaway invalidation pattern at the SwiftUI layer.

## Investigation Timeline

### 1. Static analysis (no instrumentation yet)

Before touching Instruments we inspected the Shelf view tree and the `RepositoriesFeature` reducer. Suspicions filed in priority order:

1. `ShelfView.body` recomputes `orderedShelfBooks()` on every body call. The implementation builds a `Dictionary(uniqueKeysWithValues:)` from `repositories` and routes worktree ordering through `worktreeRowSections(in:)`, which constructs a full `WorktreeRowModel` and several intermediate `Set`s per repository.
2. `.id(worktree.id)` on `ShelfOpenBookView` forces a full subtree teardown + rebuild on every book switch — including the Ghostty `NSViewRepresentable` wrappers.
3. The animation is double-applied: `ShelfView` has `.animation(.easeInOut(duration: 0.2), value: openBookID)` AND book-click handlers do `store.send(..., animation: .easeInOut(duration: 0.2))`.
4. Many spines each subscribe to `terminalManager.stateIfExists(for: book.id)`, which reads the entire `@Observable WorktreeTerminalManager.states` dictionary. Any terminal activity at all could fan out to every spine.
5. The `matchedGeometryEffect` bridging the left and right `ForEach` branches forces SwiftUI to interpolate spine identity across two separate lists.

Most of these turned out to be real but only some moved the needle.

### 2. First Instruments capture and the smoking gun (Run 1, Debug)

Animation Hitches + SwiftUI instrument template, Debug build, 25 s recording with rapid book clicking.

Top "cause edges" in `swiftui-causes`:

| Source | Cause edges |
|---|---|
| `Layout: AnimatableFrameAttribute` | 233 177 |
| `@Observable WorktreeTerminalManager.(Dictionary<String, WorktreeTerminalState>)` | 196 968 |
| `RepositorySectionView.body` | **184 681** |
| `EnvironmentWriter: KeyPressModifier` | 164 594 |
| `Layout: LayoutChildGeometries` | 124 230 |
| `@Observable CommandKeyObserver.(Bool)` | 65 891 |

`RepositorySectionView.body` running ~7400 times per second was the smoking gun. The cause was traced back to:

```swift
RepoHeaderRow(
  ...,
  tabCount: Self.openTabCount(for: repository, terminalManager: terminalManager),
  ...
)
```

`openTabCount` iterates the repository's worktrees and calls `terminalManager.stateIfExists(...)` for each — so the body of *every* sidebar repository section subscribed to changes in `WorktreeTerminalManager.states` (which churns on any terminal activity), and *every* `tabManager.tabs` array within that. Any keystroke into a single terminal could fan out to the entire sidebar.

### 3. P0 fixes (commit `0fe682cb`)

Four changes landed together:

- **P0-1**: Extract the tab-count badge into a dedicated leaf view `RepoHeaderTabCountBadge`. The leaf reads `terminalManager` itself; the parent `RepositorySectionView` no longer touches it. SwiftUI's invalidation graph stops at the badge subtree, leaving the rest of the sidebar untouched.
- **P0-2**: Rewrite `orderedShelfBooks()` to use direct `IdentifiedArray` lookup (`repositories[id:]`) and route through the lighter `orderedWorktrees(in:)` rather than `worktreeRowSections(in:)`. Avoids per-repo `WorktreeRowModel` and `Set` allocations.
- **P1-1**: Drop the redundant `animation:` parameter from Shelf-originated `store.send` calls. The view-level `.animation(value: openBookID)` already covers Shelf and left-nav-originated changes.
- Also added `OSSignposter` to `SupaLogger` and instrumented the obvious suspects (reducer cases, focus/sync calls, book-click events).

Result in the next Release-build trace:

| Metric | Before | After P0 | Δ |
|---|---|---|---|
| `RepositorySectionView.body` cause edges | 184 681 | 14 456 | **−92 %** |
| `WorktreeTerminalManager.states` cause edges | 196 968 | 14 456 | **−93 %** |
| Severe Hangs | 1 (2.02 s) | 0 | gone |

Body-storm pattern eliminated. The 2 + second main-thread death observed at baseline never reappeared in any subsequent trace. **This is the unambiguous win of the entire investigation.**

### 4. The "still feels janky" plateau

Despite P0 the user still felt visible jank. Subsequent Release traces showed:

- Hitch budget remained roughly proportional to user clicks (~250–300 ms per click)
- Hangs in the 600–1000 ms range still occurred under fast clicking
- The dominant `swiftui-causes` work shifted to layout / animation / preferences:
  - `Layout: AnimatableFrameAttribute` ~256 000
  - `EnvironmentWriter: KeyPressModifier` ~240 000
  - `Layout: LayoutChildGeometries` ~152 000
  - `View Creation / Reuse` ~138 000

These are SwiftUI-internal categories — nothing user-code we could optimize directly. We added more granular signposts to localize cost: `OpenBook.onAppear` / `onDisappear`, `Ghostty.makeNSView` / `updateNSView` / `dismantleNSView`, `ShelfView.body` / `ShelfSpineView.body` event counters.

The data was unambiguous and surprising:

| Signpost | Per-click avg / max |
|---|---|
| `reducer.selectWorktree` | 0.18 / 0.21 ms |
| `OpenBook.onAppear` | 0.10 / 0.18 ms |
| `Ghostty.makeNSView` | 0.33 / 0.60 ms |
| `focusSelectedTab` | 0.05 / 0.10 ms |
| `syncFocus` | 0.03 / 0.09 ms |
| `applySurfaceActivity` | 0.03 / 0.10 ms |

**Total instrumented user-code work over a 22 s recording with 32 clicks: ≈25 ms.** The remaining ~250 ms-per-click was happening *between* our signposts, entirely inside SwiftUI's layout / animation / display-list pipeline.

### 5. Phase 1 + Phase 2 — remove `.id(worktree.id)`

Hypothesis: the residual cost is the SwiftUI subtree teardown / remount triggered by `.id`, even though our own `makeNSView` is fast. By switching to identity-stable view reuse and migrating the focus-sync logic into `.onChange(of: worktree.id, initial: true)`, the heavy SwiftUI bookkeeping (attribute graph, preference values, accessibility nodes) for the entire ShelfOpenBookView subtree should not run per click.

Implemented in two phases for safety:

- Phase 1: add the new `onChange` path with verification-only signposts, leave `.id` in place. Trace showed `OpenBook.onChange.worktreeID` firing 1:1 with `OpenBook.onAppear` — confirmed equivalence.
- Phase 2: migrate logic, remove `.id`.

Pre-implementation we worried that `GhosttySurfaceScrollView` stores its `surfaceView` as `private let` — meaning if SwiftUI reused the wrapper across book switches via `updateNSView`, the wrapper would still display the previous book's surface. Inspection of `TerminalSplitTreeView.swift:27` showed there is already an inner `.id(node.structuralIdentity)` on `SubtreeView` that forces dismantle + make whenever the split tree changes. So the surface-binding bug was a non-issue in practice. The user confirmed visually.

Result: behaviourally clean, but **no measurable perf gain**:

| Metric | With `.id` (Run 6) | Without `.id` (Run 8) |
|---|---|---|
| Hitches per click | 262 ms | 316 ms |
| Hitch share of recording | 37 % | 39 % |
| Severe Hangs | 0 | 4 (system-pressure variance) |

Phase 2 was reverted in commit `c9b852eb`'s parent state. Lesson: the inner `.id(node.structuralIdentity)` was already forcing the heavy work, the outer one was redundant overhead but not the dominant cost.

### 6. Animation off — the perceptual experiment

Single-line change: `.animation(.easeInOut(duration: 0.2), value: openBookID)` → `.animation(nil, value: openBookID)`.

User reported: "去掉动画确实完全不卡了". But the trace told a different story:

| Metric | Animation on (Run 8) | Animation off (Run 9) |
|---|---|---|
| Hitches per click | 316 ms | 256 ms |
| Hangs | 5 | 20 |
| Hang share of recording | 83 % | 51 % |

Per-click hitch barely moved. Total main-thread blocked time even *increased* in absolute terms, with many Hangs covering windows where multiple clicks landed inside one block.

The insight: **the spine-flow animation is the perceptual jank amplifier**, not the cause. When animation is running, every missed frame produces a visible "broken animation" artefact. When animation is off, the same amount of main-thread work just becomes a small response latency that the user reads as "instant click registered, slight delay before redraw" rather than "jank".

Without further structural rewrites (e.g. lazy-rendered spines, single-`ForEach` layout to drop `matchedGeometryEffect`, or rendering spines with `Canvas` instead of one `View` each), the per-click work appears to be roughly constant.

### 7. Final decision — Option C

Restore everything that didn't have a measurable win:

- `.id(worktree.id)` back, focus logic back in `.onAppear`, Phase-2-only `onChange` path removed
- Animation back to `.easeInOut(duration: 0.2)`

Keep what is unambiguously good:

- All four P0/P1 fixes
- The `OSSignposter` toolkit on `SupaLogger` (`PointsOfInterest` category for stock-instrument visibility)
- Body counters and lifecycle signposts as long-term observability — they cost nothing when no Instruments session is attached

Net commits on `perf/shelf-jank-fixes`:

- `0fe682cb` perf(shelf): cut sidebar tab-count subscription storm and add signposts
- `c9b852eb` chore(shelf): add long-term performance signposts

## What Worked vs What Didn't

| Change | Cost | Outcome |
|---|---|---|
| **P0-1**: leaf view for sidebar tab count | ~30 lines | RepositorySectionView body invocations −92 %, killed the Severe Hang completely. **Kept.** |
| **P0-2**: rewrite `orderedShelfBooks()` | ~20 lines | Eliminated per-frame Dict/Set allocations on the ShelfView hot path. **Kept.** |
| **P1-1**: drop redundant action animation | 4 line touch | Removed double-animation transactions. Marginal but free. **Kept.** |
| `OSSignposter` toolkit + signposts | ~80 lines, multiple files | Made every subsequent investigation tractable. **Kept.** |
| Phase 2: remove `.id(worktree.id)` | ~30 lines | No measurable perf gain; lost `.transition(.opacity)`. **Reverted.** |
| Animation duration 0.2 s → 0.1 s | 1 line | Hitch per click 285 → 244 ms (−14 %). Not enough to justify UX change. **Reverted.** |
| Animation off entirely | 1 line | Felt smooth but trace showed work was unchanged. UX trade-off not worth perceptual-only win. **Reverted.** |

## Methodology and Tooling Learned

### `xctrace` from the command line

`/usr/bin/xctrace` is a stub; the real tool ships inside Xcode at `/Applications/Xcode-26.4.1.app/Contents/Developer/usr/bin/xctrace`. Trying to inspect a trace recorded by Xcode 26.x with the system stub produces `Cannot load existing document because of an error: Missing features` — silent and confusing. Always use the Xcode-bundled binary:

```bash
XCT="/Applications/Xcode-26.4.1.app/Contents/Developer/usr/bin/xctrace"

# Discover what data is in the trace
"$XCT" export --input run.trace --toc --output toc.xml

# Pull a specific schema
"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' \
  --output hangs.xml

# Filter further by attribute (e.g. signposts under PointsOfInterest)
"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"][@category="PointsOfInterest"]' \
  --output poi.xml
```

Useful schemas that consistently held data:

- `potential-hangs` — main-thread block intervals with hang-type classification
- `hitches` — per-frame hitch events, often with a narrative description
- `os-signpost` — Begin/End/Event records, one table per attribute filter
- `swiftui-causes` — view dependency graph edges, the most useful single source for finding invalidation storms
- `swiftui-update-groups` — SwiftUI-internal update transactions with duration

The XML export uses an aggressive `id`/`ref` interning pattern. To aggregate counts you must build a per-trace `id → label` table from the first definition and then resolve refs. A simple Python script walks the rows in a single pass; the bigger files (1 GB+ for `swiftui-updates` on a 25 s recording) needed buffered streaming.

### Animation Hitches template's signpost filter is hard-coded

The stock Animation Hitches template includes an `os_signpost` instrument, but it's filtered to `subsystem == "com.apple.ConditionInducer.LowSeverity"` — i.e. only Apple's internal conditioning signposts. Our subsystem (`com.onevcat.prowl`) is not captured by default. Two ways to make app signposts visible in this template:

1. Add a generic `os_signpost` instrument to the trace document and configure it manually (subsystem filter or empty).
2. **Use the well-known `"PointsOfInterest"` category** for the signposter. The stock **Points of Interest** instrument is hard-coded to that category and shows app signposts without further configuration. This is what `SupaLogger` does now.

We learned (1) the hard way in Run 3 and (2) when Run 4's "Points of Interest" lane stayed empty even with our signposts emitted.

### Hangs vs Hitches

These are not the same thing and Animation Hitches reports them in two different lanes:

- A **Hang** is a contiguous main-thread block longer than the configured threshold (default 33 ms; surfaces as Microhang, Hang, or Severe Hang). Stack traces are sometimes attached.
- A **Hitch** is one or more consecutive frames missing vsync. Multiple frames missed in a row collapse into one hitch event with a longer duration. Hitches do not require the main thread to be blocked — GPU / render-server / commit-phase issues all surface as hitches.

A trace can have many Hitches and zero Hangs (frame production too slow to keep up with vsync but main thread always yielding within 33 ms — exactly what Run 4 looked like). It can also have many Hangs and very visible jank. The two metrics measure different aspects of "slow" and need to be read together.

### Signpost begin/end with `inout` state

`SupaLogger.interval(_:_:)` takes a closure, but TCA reducer cases bind `state` as `inout` and Swift cannot capture `inout` parameters in a non-escaping closure. The workaround is a manual `beginInterval` / `endInterval` token API:

```swift
case .selectWorktree(let id, let focusTerminal):
  let token = repositoriesLogger.beginInterval("reducer.selectWorktree")
  defer { repositoriesLogger.endInterval(token) }
  // ... mutate state directly ...
```

The token wraps `OSSignpostIntervalState` so callers don't need to import `OSLog` themselves.

### Signpost inside SwiftUI `body`

`var body: some View` is implicitly `@ViewBuilder` and rejects `defer`. To count body invocations, an `Event` signpost via a discarded `let _ =` works:

```swift
var body: some View {
  let _ = shelfLogger.event("ShelfView.body")
  // ... view tree ...
}
```

Body intervals (Begin/End) are not directly representable this way; use the SwiftUI instrument's "View Body" track instead when you need duration.

### `OSSignposter.emitEvent` doesn't always show up in `xctrace export`

In our traces, `Begin` and `End` rows from `interval(_:)` consistently appeared, but `emitEvent` (point signposts) sometimes didn't show in the exported `os-signpost` table even though they were visible in the Instruments UI. Worth knowing if a signpost count looks low — verify in the UI before assuming the call site didn't fire.

## Conclusions

1. **The single biggest win was finding the observability storm in `RepositorySectionView`**. Static analysis spotted the suspicious read; `swiftui-causes` confirmed it; the leaf-view fix dropped it ~92 % and eliminated the Severe Hang. This is what to look for first when SwiftUI feels uniformly slow under any state change.

2. **`@Observable` types must be subscribed to with care.** Reading any property of an `@Observable` instance inside a parent `body` subscribes that body to *every change* on that property — and properties of type `Dictionary<…>` or `Set<…>` change on every insert / remove / mutate. For values that change frequently, push the read down into a leaf view that only renders that one value. The leaf still re-renders frequently, but the parent (and its other children) doesn't.

3. **Animation amplifies perceived jank far beyond its actual contribution to work.** The same ~250 ms of main-thread work feels broken when an animation is running through it and feels merely "slightly slow" when it isn't. Removing animation can be the right product call even when the trace numbers don't shift.

4. **`.id(viewIdentity)` is not free.** Even when our own `makeNSView` body is fast, the SwiftUI bookkeeping around full subtree teardown (attribute graph, preferences, accessibility, transition orchestration) is real. But removing it may not yield measurable perf if there's another `.id` deeper in the tree forcing the same work — read the layout of `.id` modifiers across the whole subtree before assuming a removal will help.

5. **Signposts pay for themselves on the second investigation.** They cost nothing when no Instruments session is attached and let us collapse 30 minutes of guess-and-trace into a single targeted measurement. Worth keeping permanently around hot paths.

## Open Questions / Future Work

If we ever decide to attack the residual ~250 ms-per-click cost (probably only worthwhile if user feedback escalates):

- **Lazy-render spines**. We always render every spine even when many are off-screen. A `ScrollView` + `LazyHStack` could cap the work to the visible window.
- **Single-`ForEach` Shelf layout**. Drop the cross-`ForEach` `matchedGeometryEffect` by laying out spines in one list and overlaying / inline-expanding the open book area at the right index. SwiftUI's normal list-diff would handle spine flow without identity reconciliation across two lists.
- **`Canvas`-rendered spines**. Each spine is currently a `View` subtree with `Button`s, `ScrollView`, `.contextMenu`, `.help` etc. Cumulatively across ~10 spines this is a lot of view-tree work per click. A custom `Canvas`-based spine could cut SwiftUI's per-spine overhead by an order of magnitude — at the cost of having to reimplement hover, hit-testing, accessibility manually.
- **Eliminate the inner `.id(node.structuralIdentity)`**. We never tested this. It might let the surface wrappers be reused across compatible split-tree shapes, but `GhosttySurfaceScrollView.surfaceView` is `let` so we'd have to make it mutable and audit all attach/detach lifecycle paths first.

None of these are obviously worth doing today.

## Long-Term Observability Hooks

After this investigation the following signposts are permanently emitted to the `com.onevcat.prowl` subsystem under the `PointsOfInterest` category. They are visible in Instruments by adding the stock **Points of Interest** instrument to any trace:

- Reducer paths: `reducer.selectWorktree`, `reducer.selectRepository` (intervals)
- Terminal lifecycle: `Ghostty.makeNSView`, `Ghostty.updateNSView` (intervals); `Ghostty.dismantleNSView` (event)
- Shelf focus / sync: `OpenBook.onAppear`, `OpenBook.onChange.selectedTabId`, `focusSelectedTab`, `syncFocus`, `applySurfaceActivity` (intervals); `OpenBook.onDisappear` (event)
- View invalidation counters: `ShelfView.body`, `ShelfSpineView.body` (events)
- User-input markers: `BookClick.SwitchBook`, `BookClick.TabSwitchSameBook`, `BookClick.NewTabSpine` (events)

For future Shelf perf debugging the recommended starting workflow is:

1. Record with Animation Hitches template
2. Add the **Points of Interest** instrument to the document (one click)
3. Reproduce the workload
4. In the timeline, line up Hitches / Hangs against the Points of Interest lane to see which named work is on the critical path
