# Shelf Book-Switch Jank Investigation

Last updated: 2026-04-29
Status: Closed for now. The current branch keeps the fixes that improved trace data or UX without visible regressions, and drops the later experiments that introduced artifacts or reduced interaction quality.

## Summary

Switching books quickly in Shelf mode showed visible frame drops, especially when switching with keyboard shortcuts. The first investigation pass found a large SwiftUI invalidation storm in the sidebar. The second pass narrowed the keyboard-path cost and simplified the Shelf spine layout.

The retained changes are:

- `RepositorySectionView` no longer reads `WorktreeTerminalManager.states` just to render the tab-count badge. The read moved into a leaf view so invalidation stops at the badge.
- `orderedShelfBooks()` avoids per-body `Dictionary`, `Set`, and full `WorktreeRowModel` construction.
- Shelf-originated book switches no longer send an extra TCA animation transaction on top of the view-level `openBookID` animation.
- `CommandKeyObserver` only enters shortcut-hint mode for bare Command or bare Control, not every shortcut chord containing Command/Control.
- The sidebar key-forwarding `.onKeyPress` modifier is not installed while Shelf is active. This removed the `EnvironmentWriter: KeyPressModifier` invalidation path from the Shelf switching trace.
- Shelf spines are rendered from a single `ForEach`, removing the cross-list `matchedGeometryEffect` between left/right spine stacks.
- The open-book opacity transition was removed. Trace improvement was small, but the user reported no visible UX regression, so it is kept as a low-risk cleanup.
- Long-term signposts remain in place for future regressions.

Experiments that were tried and rejected:

- Removing `.id(worktree.id)` from `ShelfOpenBookView`. It was behaviorally safe but gave no measurable win.
- Fully disabling or isolating the Shelf animation. It either only improved perception or caused visible terminal animation loss.
- Rendering the terminal/open area in an overlay outside the spine layout animation. This created a black-edge artifact during spine movement and made several SwiftUI cause counters worse.
- Removing context menus from closed-spine tab slots. This hurt interaction and did not improve hitches.

## Final Trace Shape

The final useful comparison line is run13/run15, after the keyboard-path and single-`ForEach` fixes. Hangs were treated as unreliable in this phase because they appeared and disappeared across similar runs; hitches and SwiftUI cause edges were more useful.

| Run | Main change | Selects | All hitches/select | Select-window hitches/select | Key SwiftUI result |
| --- | --- | ---: | ---: | ---: | --- |
| run10 | Rejected terminal animation isolation experiment | 25 | 296.5 ms | not used | UX regression; terminal animation disappeared |
| run11 | Bare Command/Control hint mode | 25 | 235.7 ms | 186.7 ms | `@Observable CommandKeyObserver.(Bool)` disappeared; `KeyPressModifier` fell to 116,284 source edges |
| run12 | Disable sidebar key forwarding in Shelf | 29 | 196.1 ms | 151.7 ms | `EnvironmentWriter: KeyPressModifier` fell to 0; `WorktreeRowsView.body [skipped]` fell sharply |
| run13 | Single `ForEach`, no matched geometry | 29 | 176.4 ms | 144.4 ms | `Layout: MatchedFrame` fell to 0; `LayoutChildGeometries` source edges fell from 111,421 to 4,279 |
| run14 | Rejected terminal overlay | 29 | 167.1 ms | 136.3 ms | Small hitch win, but `AnimatableFrameAttribute`, responders, and opacity renderer all worsened; visible black edge |
| run15 | Remove open-book opacity transition | 28 | 250.6 ms | 140.3 ms | Small select-window win; outside-window hitches dominated all-hitch total |
| run16 | Rejected context-menu scoping | 27 | 180.6 ms | 145.1 ms | Interaction regression; `View Responders` worsened |

`select-window hitches/select` is the preferred number for book-switch work because it only counts hitches between the first and last `reducer.selectWorktree` signpost. The "all hitches/select" number can be dominated by startup, recording, or unrelated post-workload spikes, as run15 shows.

## Problem

Quickly switching between Shelf books produced obvious frame drops. Initial Instruments captures showed:

- severe hangs in early traces, including one multi-second main-thread block
- hundreds of thousands of SwiftUI update/cause edges in short recordings
- visible animation breakage during the 0.2 s spine-flow animation

The problem was not one slow reducer or one slow `NSViewRepresentable`. The reducer and Ghostty bridge signposts consistently measured in sub-millisecond ranges. The heavy work was mostly SwiftUI invalidation, layout, responder, and display-list work between our signposts.

## Investigation Timeline

### 1. Static Suspicions

The first static pass identified several plausible sources:

1. `ShelfView.body` recomputes `orderedShelfBooks()` on every body call.
2. `.id(worktree.id)` on `ShelfOpenBookView` might force expensive subtree teardown.
3. Shelf book switching was applying animation twice: once in the TCA action send and once via `.animation(value: openBookID)`.
4. Sidebar repository rows read `terminalManager.stateIfExists(...)` while rendering tab counts.
5. The Shelf layout split spines across left/right `ForEach` lists and bridged identity with `matchedGeometryEffect`.
6. Keyboard-based switching might be over-invalidating shortcut hint UI through `CommandKeyObserver` and `.onKeyPress`.

Most of these were real; only some moved user-visible performance.

### 2. Sidebar Tab-Count Subscription Storm

Early `swiftui-causes` data showed `RepositorySectionView.body` and `@Observable WorktreeTerminalManager.(Dictionary<String, WorktreeTerminalState>)` as top offenders.

The cause was:

```swift
RepoHeaderRow(
  ...,
  tabCount: Self.openTabCount(for: repository, terminalManager: terminalManager),
  ...
)
```

`openTabCount` iterated worktrees and called `terminalManager.stateIfExists(...)` from the parent sidebar row. That subscribed every repository section body to the global terminal state dictionary, so unrelated terminal activity fanned out through the sidebar.

Fixes landed in `0fe682cb`:

- Move tab-count reads into `RepoHeaderTabCountBadge`.
- Rewrite `orderedShelfBooks()` to use direct repository/worktree ordering.
- Remove the redundant Shelf-originated action animation.
- Add `SupaLogger` signpost helpers and focused Shelf/Ghostty signposts.

Result:

| Metric | Before | After |
| --- | ---: | ---: |
| `RepositorySectionView.body` cause edges | 184,681 | 14,456 |
| `WorktreeTerminalManager.states` cause edges | 196,968 | 14,456 |
| Severe hangs from this storm | present | gone |

This was the largest unambiguous win.

### 3. `.id(worktree.id)` Experiment

Hypothesis: the residual cost came from `ShelfOpenBookView` teardown/remount on every book switch.

We tried migrating focus logic into `onChange(of: worktree.id, initial: true)` and removing the outer `.id(worktree.id)`. This behaved correctly, but trace data did not improve. The likely reason is that a deeper `.id(node.structuralIdentity)` in the terminal split tree already forces the relevant Ghostty surface wrapper lifecycle work.

Decision: reverted. The extra code was not worth keeping.

### 4. Animation Experiments

Disabling the root Shelf animation made the UI feel much smoother, but traces showed the work mostly remained. This clarified that animation was a perception amplifier: missed frames are much more visible when the spine is supposed to glide.

A later attempt to isolate book-switch animation around the spine stacks and disable it around the terminal area also failed product-wise. The terminal animation disappeared and the trace did not justify the UX loss.

Decision: keep the normal spine-flow animation.

### 5. Keyboard-Path Fixes

The user reproduced the problem primarily with shortcuts. run8/run10 showed high `@Observable CommandKeyObserver.(Bool)` and `EnvironmentWriter: KeyPressModifier` cost.

Two fixes were retained:

- `CommandKeyObserver.shouldShowShortcuts(for:)` now returns true only for bare Command or bare Control, not shortcut chords such as Control+number or Command+Shift.
- `SidebarListView` does not install its sidebar-to-terminal `.onKeyPress` forwarding modifier while Shelf is active.

Results:

- run11 removed `@Observable CommandKeyObserver.(Bool)` from the hot SwiftUI causes.
- run12 removed `EnvironmentWriter: KeyPressModifier` from the Shelf switching path entirely.
- `WorktreeRowsView.body [skipped]` dropped from 26,466 in run11 to 2,853 in run12.
- select-window hitches/select improved from 186.7 ms in run11 to 151.7 ms in run12.

The behavior trade-off is narrow: while Shelf is active and the sidebar has focus, ordinary typed characters are no longer forwarded into the selected terminal. Direct terminal input is unaffected.

### 6. Single-`ForEach` Shelf Layout

The original Shelf layout split spines into left and right stacks:

```swift
left spines
open book area
right spines
```

Because a book moved between the two `ForEach` subtrees when the open index changed, the code used `matchedGeometryEffect` to bridge identity.

The retained rewrite renders all spines from a single `ForEach(books)` and inserts the open book area after the open book. This lets normal SwiftUI diffing preserve spine identity without matched geometry.

run13 results:

| Metric | run12 | run13 |
| --- | ---: | ---: |
| select-window hitches/select | 151.7 ms | 144.4 ms |
| SwiftUI cause rows | 1,303,129 | 1,026,467 |
| `Layout: MatchedFrame` source | 18,030 | 0 |
| `Layout: LayoutChildGeometries` source | 111,421 | 4,279 |
| `View Responders` dest | 102,928 | 69,228 |
| opacity renderer dest | 72,073 | 57,078 |

Decision: kept. The trace win was moderate and the user reported a clear subjective improvement.

### 7. Terminal Overlay Experiment

Hypothesis: keep spines animating, but remove the real terminal subtree from the animated `HStack`. Use a lightweight placeholder in the layout and render the terminal in an overlay at its final frame.

run14 showed a small hitch win, but the approach had two problems:

- Visual artifact: during spine movement the terminal overlay was already at the new position, while the old layout area exposed the window background, producing a black edge.
- SwiftUI causes got worse:
  - `AnimatableFrameAttribute` source increased from 135,581 to 164,827.
  - `View Responders` dest increased from 69,228 to 75,033.
  - opacity renderer dest increased from 57,078 to 70,036.

Decision: reverted. The small hitch improvement did not justify the artifact and added complexity.

### 8. Open-Book Opacity Transition Removal

Removing the explicit `.transition(.opacity)` from `openBookArea` produced only a small win:

| Metric | run13 | run15 |
| --- | ---: | ---: |
| select-window hitches/select | 144.4 ms | 140.3 ms |
| select-window max hitch | 125.0 ms | 116.7 ms |
| `AnimatableFrameAttribute` source/select | 4,675 | 4,588 |

Several opacity-related SwiftUI causes did not improve after normalization, so this is not a major root-cause fix. However, the user reported no visible behavior regression, so it was kept as a simple low-risk improvement.

### 9. Closed-Spine Tab Context Menu Experiment

Hypothesis: closed spines did not need a full tab context menu, and removing it might reduce `View Responders` and the `TerminalTabContextMenu` view-list cost.

Implementation: only the open spine retained full tab context menus.

Result: rejected.

- select-window hitches/select regressed from 140.3 ms to 145.1 ms.
- `View Responders` dest/select worsened from 2,296 to 3,133.
- The old `ModifiedContent<ShelfSpineTabSlot, TerminalTabContextMenu>` shape was replaced by `_ConditionalContent<ModifiedContent, ShelfSpineTabSlot>`, so SwiftUI still had view-list complexity.
- Closed-spine right-click behavior got worse.

Decision: reset away. Do not optimize context menus by conditionally changing the child view type.

## What Worked vs What Did Not

| Change | Outcome |
| --- | --- |
| Sidebar tab-count leaf view | Large win. Removed the biggest invalidation storm. Kept. |
| Faster `orderedShelfBooks()` | Small/free hot-path cleanup. Kept. |
| Remove redundant action animation | Small/free cleanup. Kept. |
| Signpost toolkit and focused signposts | Made every later trace tractable. Kept. |
| Bare Command/Control shortcut-hint mode | Clear win for keyboard switching. Kept. |
| Disable sidebar `.onKeyPress` while Shelf is active | Clear win; removed `KeyPressModifier` from Shelf switching trace. Kept. |
| Single `ForEach` Shelf layout | Moderate trace win and good subjective win. Kept. |
| Remove open-book opacity transition | Small trace win, no observed UX cost. Kept. |
| Remove outer `.id(worktree.id)` | No measurable win. Reverted. |
| Disable/isolate animation | Either perceptual-only or visual regression. Reverted. |
| Terminal overlay outside layout animation | Small hitch win but black-edge artifact and worse causes. Reverted. |
| Closed-spine context-menu scoping | Worse trace and worse UX. Reset away. |

## Current Conclusions

1. **The worst problem was not the terminal.** Reducer work, Ghostty `makeNSView`, focus, and sync signposts are all tiny relative to the hitch windows.

2. **The first major class was invalidation fan-out.** Sidebar tab counts, shortcut hints, and `.onKeyPress` environment machinery were multiplying work across unrelated views.

3. **The second major class is SwiftUI layout animation.** After invalidation storms were removed, the dominant costs became `AnimatableFrameAttribute`, `External: Time`, `View Responders`, and display-list renderer effects. These are consequences of animating a dense interactive SwiftUI tree.

4. **Hangs were too unstable to use as the deciding metric in later runs.** The same user-visible workload could show very different hang counts. Hitches and normalized SwiftUI cause edges were more reliable.

5. **Animation changes must be judged by both trace and eye.** Disabling animation can feel much better while barely moving work. Conversely, moving terminal rendering out of layout improved hitches slightly but created visible artifacts.

6. **Stable view shape matters.** The closed-spine context-menu experiment showed that replacing one expensive modifier with a conditional child shape can shift cost instead of reducing it.

## Methodology and Tooling Learned

### `xctrace` from the command line

`/usr/bin/xctrace` is a stub; use the Xcode-bundled tool. In this investigation the working path was:

```bash
XCT="/Applications/Xcode-26.4.1.app/Contents/Developer/usr/bin/xctrace"

"$XCT" export --input run.trace --toc --output toc.xml

"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' \
  --output hitches.xml

"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' \
  --output hangs.xml

"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"][@category="PointsOfInterest"]' \
  --output poi.xml

"$XCT" export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="swiftui-causes"]' \
  --output swiftui-causes.xml
```

The XML export interns values with `id`/`ref`. Aggregation scripts must resolve refs; a streaming parser is necessary for large `swiftui-causes` and `swiftui-updates` exports.

### Signposts

`SupaLogger` emits signposts under subsystem `com.onevcat.prowl` and category `PointsOfInterest`. This category is visible in the stock Points of Interest instrument.

Reducer code that mutates `inout state` should use manual begin/end tokens:

```swift
case .selectWorktree(let id, let focusTerminal):
  let token = repositoriesLogger.beginInterval("reducer.selectWorktree")
  defer { repositoriesLogger.endInterval(token) }
  // mutate state
```

SwiftUI bodies can use event signposts:

```swift
var body: some View {
  let _ = shelfLogger.event("ShelfView.body")
  // view tree
}
```

### Hangs vs Hitches

- A **Hang** is a main-thread block longer than the threshold.
- A **Hitch** is one or more missed frames.

They measure different failure modes. For this investigation, hitches normalized by `reducer.selectWorktree` count were the most useful metric.

## Future Work

The current result is probably good enough. If Shelf book switching becomes a product priority again, the remaining useful directions are more structural:

- **Custom spine layout instead of animated `HStack` frame interpolation.** Compute spine positions directly and animate transforms/offsets with stable child identity. This is more invasive but targets `AnimatableFrameAttribute` directly.
- **Reduce per-spine interactivity in a stable way.** Avoid conditional child types; consider stable lightweight wrappers if responder cost becomes a proven bottleneck.
- **Lazy or virtualized spines.** Useful only if real users commonly have many more visible/open books than the current test set.
- **Audit the inner terminal split-tree `.id(node.structuralIdentity)`.** This may be risky because `GhosttySurfaceScrollView` currently stores its surface view as immutable state; changing it needs a careful lifecycle audit.
- **Canvas-rendered spines.** Potentially large reduction in SwiftUI view-tree work, but high implementation and accessibility cost.

Do not re-try these unless a new trace suggests a different result:

- removing only the outer open-book `.id`
- fully disabling Shelf animation
- moving terminal content to a final-position overlay
- conditionally removing closed-spine context menus

## Long-Term Observability Hooks

Permanent signposts retained for future Shelf debugging:

- Reducer paths: `reducer.selectWorktree`, `reducer.selectRepository`
- Terminal lifecycle: `Ghostty.makeNSView`, `Ghostty.updateNSView`, `Ghostty.dismantleNSView`
- Shelf focus/sync: `OpenBook.onAppear`, `OpenBook.onChange.selectedTabId`, `focusSelectedTab`, `syncFocus`, `applySurfaceActivity`, `OpenBook.onDisappear`
- View counters: `ShelfView.body`, `ShelfSpineView.body`
- User markers: `BookClick.SwitchBook`, `BookClick.TabSwitchSameBook`, `BookClick.NewTabSpine`

Recommended future workflow:

1. Record with Animation Hitches template.
2. Add the Points of Interest instrument.
3. Reproduce the workload.
4. Export `hitches`, `os-signpost`, and `swiftui-causes`.
5. Normalize hitches by `reducer.selectWorktree` count and inspect SwiftUI source/destination pairs.
