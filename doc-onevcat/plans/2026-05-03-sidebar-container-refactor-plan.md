# Sidebar Container Refactor Plan

Status: planning
Issue: [#249](https://github.com/onevcat/Prowl/issues/249)
Related: [#222](https://github.com/onevcat/Prowl/issues/222)

## Goal

Refactor the repository sidebar so each repository behaves as one stable visual and drag unit, while worktrees remain selectable, reorderable, and efficient to update.

This should fix the structural mismatch where the app treats repositories as reorderable units but SwiftUI `List` sees repository headers and worktree rows as separate rows. That mismatch shows up as:

- incorrect repository drag insertion indicators when dragging downward across expanded repositories
- unstable bulk expand/collapse animations
- potential sidebar flicker during drag when live terminal, notification, or ordering updates arrive

## Current Findings

### 1. Repository sections are not actual list rows

`SidebarListView` renders repositories through an outer `ForEach(...).onMove`.

`RepositorySectionView` then returns:

```swift
Group {
  header
    .tag(SidebarSelection.repository(repository.id))
  if isExpanded {
    WorktreeRowsView(...)
  }
}
```

In practice, the outer data model says "repository row", but `List` receives separate rows:

```text
Repository A header
  Repository A worktree
  Repository A worktree
Repository B header
  Repository B worktree
```

This explains the observed downward-drag indicator bug:

```text
Target Repo header
o-----------
Target Repo worktree
```

SwiftUI is placing the indicator between list rows. It does not know that the target repository header and its worktree rows should be treated as one repository-level drop zone.

### 2. `List(selection:)` is doing too much

The current `List` carries several behaviors at once:

- archived worktree selection and repository list header
- repository row selection for plain folders
- worktree multi-selection
- repository expand/collapse
- native repository reorder
- native worktree reorder for pinned and unpinned groups
- reveal-in-sidebar via `ScrollViewReader.scrollTo`
- native sidebar styling and accessibility

Canvas, Shelf, and the footer are not `List` rows today; they are safe-area inset chrome around the list. The refactor should preserve that boundary unless a later design intentionally moves them into the scroll content.

### 3. Live state still reaches rows during drag

Some expensive state reads have already been isolated, such as moving repository tab-count reads into `RepoHeaderTabCountBadge`.

Remaining drag-time churn sources include:

- `WorktreeRowsView` animates changes to `rowIDs`
- each worktree row reads terminal notification/task/run-script state
- notification-driven reorder can call `withAnimation(.snappy)` and mutate `worktreeOrderByRepository`
- row hover/action UI changes while a drag session is active

These are not necessarily the root cause of the drop-indicator bug, but they are credible contributors to #222-style flicker.

## Revised Direction

Use a custom sidebar scroll container rather than trying to keep the current flat `List` structure.

Execution order matters: first stabilize the old `List` path with a reducer-level drag gate, then replace the visual structure. The drag gate is a hard prerequisite because it reduces #222 risk before the broader #249 rewrite starts.

Recommended shape:

```text
SidebarView chrome
├── top safeAreaInset buttons
│   ├── Canvas
│   └── Shelf
├── ScrollViewReader
│   └── ScrollView
│       └── LazyVStack or VStack
│           ├── repository list header
│           ├── RepositoryContainerRow
│           │   ├── RepositoryHeaderRow
│           │   └── WorktreeRows
│           ├── FailedRepositoryRow
│           └── ArchivedWorktreesRow
└── bottom safeAreaInset footer
```

Key property: repository containers are the only repository-level siblings in the outer stack. Expanded worktrees are children inside the container, not siblings beside it.

This aligns UI boundaries with model boundaries:

- repository reorder indicators target repository containers
- expand/collapse animates inside a container
- worktree reorder indicators target worktree rows inside one container
- live worktree updates do not change the outer repository list shape

## Options Considered

### Option A: Keep `List`, wrap worktrees inside one repository row

Pros:

- preserves some native sidebar styling
- repository-level `onMove` might remain mostly native

Cons:

- nested selectable worktree rows inside a single `List` row no longer participate naturally in `List(selection:)`
- worktree-level `onMove` becomes awkward inside a row
- native selection and keyboard behavior still need replacement
- likely keeps a hard-to-debug mix of native and custom drag logic

This option reduces the indicator bug but does not cleanly solve the broader sidebar design.

### Option B: Move fully to `ScrollView` + explicit rows

Pros:

- model and visual structure match
- repo and worktree drag/drop can be made explicit and testable
- selection, focus, and reveal behavior are owned by our code instead of `List` side effects
- easier to freeze drag-time updates intentionally
- eliminates `List` cell reuse as a class of expand/collapse animation bugs

Cons:

- must replace native `List(selection:)`
- must rebuild keyboard navigation, multi-selection, reorder, and accessibility affordances
- more implementation work

This remains the recommended route for #249 if the goal is "fix the sidebar design once" rather than patch one symptom.

### Option C: Short-term drag-time freeze only

Pros:

- small
- may help #222 flicker

Cons:

- does not fix repository insertion indicator because row boundaries remain wrong
- leaves the main structural mismatch in place

This is now the mandatory M1 prerequisite for Option B, not a replacement for Option B.

## Hard Requirements

The refactor must preserve these behavior and state contracts.

### Reducer actions and persistence

- Keep the existing reducer actions and persistence paths for repository and worktree ordering unless a later implementation note explicitly proves a rename is worth it.
- Preserve calls behind repository reorder, pinned worktree reorder, unpinned worktree reorder, and notification-driven reorder.
- Treat failed repository reorder semantics as an explicit product decision:
  - either failed repository rows are reorderable and their order persists through the same root ordering path
  - or they are not reorderable and the UI gives consistent feedback with no insertion target around them

### Expanded and collapsed state

- Preserve `@Shared` write-back semantics for collapsed repository IDs.
- Preserve cleanup of invalid collapsed IDs when repository IDs change.
- Ensure bulk expand/collapse and single expand/collapse share the same model path.

### Focused actions and selection synchronization

- Preserve `SidebarView` focused values for `confirmWorktreeAction`, `archiveWorktreeAction`, `deleteWorktreeAction`, and `visibleHotkeyWorktreeRows`.
- Preserve the `sidebarSelections -> setSidebarSelectedWorktreeIDs` synchronization currently owned by `SidebarView`.
- Do not regress menu commands or numbered worktree hotkeys when replacing `List(selection:)`.

### Existing row affordances

- Preserve repository and worktree context menus.
- Preserve drag previews.
- Preserve current worktree row type-select behavior. Worktree rows currently use `.typeSelectEquivalent("")`; V1 should keep type-select effectively disabled for those rows.
- Preserve root-level `dropDestination(for: URL.self)` on the sidebar container, including drops into blank sidebar space.

### Ordered roots

- Converge the current `orderedRoots.isEmpty` fallback and non-empty custom-order path into one presentation path.
- The empty ordered-roots case is a valid user state and must have tests.

## Proposed Architecture

### SidebarPresentation

Introduce a pure presentation model that flattens current repository state into explicit sidebar units.

Suggested model:

```swift
struct SidebarPresentation: Equatable {
  var items: [SidebarItem]
}

enum SidebarItem: Equatable, Identifiable {
  case listHeader(SidebarListHeaderModel)
  case repository(SidebarRepositoryContainerModel)
  case failedRepository(FailedRepositoryModel)
  case archivedWorktrees(ArchivedWorktreesRowModel)
}

struct SidebarRepositoryContainerModel: Equatable, Identifiable {
  var repositoryID: Repository.ID
  var title: String
  var rootURL: URL
  var kind: Repository.Kind
  var isExpanded: Bool
  var isRemoving: Bool
  var worktreeSections: WorktreeRowSections
}
```

Rules:

- build `SidebarPresentation` from reducer/state-side pure functions or equivalent helpers
- outer `items` contains one item per repository, not one item per row
- worktree sections remain inside the repository container
- presentation construction is pure and unit-tested
- high-frequency terminal notification/task/run-script state stays in leaf views, not in broad presentation state
- Canvas, Shelf, and footer chrome remain outside `SidebarPresentation` in V1

### Selection

Replace `List(selection:)` with explicit selection handling.

Keep `RepositoriesFeature.State.selection` and `sidebarSelectedWorktreeIDs` as the source of truth, but route clicks through helper functions.

Compatibility matrix:

| Interaction | State behavior | Focus behavior |
| --- | --- | --- |
| Canvas button | Selects Canvas and clears incompatible sidebar worktree selection. | Does not focus a terminal. |
| Shelf button | Selects Shelf and clears incompatible sidebar worktree selection. | Does not focus a terminal. |
| Archived worktrees row | Selects archived worktrees and clears incompatible worktree selection. | Does not focus a terminal. |
| Git repository header click | Toggles expanded state by default. | Does not focus a terminal. |
| Plain folder repository click | Selects the repository. | Does not focus a terminal unless current behavior already does. |
| Worktree row normal click | Selects one worktree and updates sidebar selected worktree IDs to that one ID. | Focuses the terminal for the selected worktree. |
| Worktree row Cmd-click | Toggles membership in sidebar selected worktree IDs, preserving multi-select priority. | Does not steal focus unless the resulting primary selection changes by existing rules. |
| Empty sidebar selection | Clears sidebar selected worktree IDs. | Does not focus a terminal. |

Selection visuals should be explicit in `RepositoryHeaderRow` and `WorktreeRow`, not inherited from `List`.

### Keyboard Navigation

Preserve the existing command actions first:

- `selectNextWorktree`
- `selectPreviousWorktree`
- `revealSelectedWorktreeInSidebar`
- numbered hotkeys

Do not try to rebuild full Finder-like keyboard navigation in the first pass unless it is currently user-visible and relied upon.

Required V1 behavior:

- command shortcuts still select worktrees
- selected row is scrolled into view on reveal
- focus returns to terminal after single worktree selection
- sidebar focus does not accidentally forward text while Canvas, Shelf, or Archived rules say it should not

### Repository Reorder

Replace `ForEach(...).onMove` with explicit repository drag/drop.

Suggested approach:

- make `RepositoryContainerRow` draggable with repository ID payload
- render a custom repository insertion indicator between repository containers
- compute drop destination as a repository index
- dispatch existing repository-ordering actions or a new reducer action that delegates to the same persistence path

The custom indicator should always render at repository container boundaries:

```text
Target Repo header
  Target Repo worktree
o-----------
```

This directly fixes the current downward-drag indicator bug.

### Worktree Reorder

Keep worktree reorder scoped inside one repository container.

Suggested approach:

- worktree rows are draggable with worktree ID payload
- pinned and unpinned sections keep separate drop zones
- main and pending rows remain non-movable
- drop destination maps to existing reducer actions:
  - `.pinnedWorktreesMoved(repositoryID, offsets, destination)`
  - `.unpinnedWorktreesMoved(repositoryID, offsets, destination)`

Cross-repository worktree drag can stay out of scope. The current model does not appear to support moving worktrees between repositories.

### Drag-Time Freeze

Add sidebar drag state at reducer level and use it in both the old and new sidebar paths.

During any sidebar drag:

- freeze hover-only row actions
- hide pull request / notification popover affordances that resize rows
- suppress row-ID animations caused by notification-driven reorder
- defer "move notified worktree to top" until drag ends, or apply it without animation after drop

Reducer behavior:

- drag begin records that sidebar drag is active
- `worktreeNotificationReceived` while drag is active records pending reorder IDs instead of mutating row order immediately
- drag end flushes pending notification reorders in deterministic order, dropping stale worktree IDs
- `moveNotifiedWorktreeToTop == false` remains a no-op

This addresses #222 without requiring every live data read to stop.

### Expand / Collapse

Move expand/collapse animation into `RepositoryContainerRow`.

Rules:

- outer repository container identity must not change when worktrees appear/disappear
- single repo expand/collapse animates child rows inside the container
- bulk expand/collapse updates many containers, but the outer stack still has stable repository items
- avoid animating row identity and live status changes in the same transaction

### Reveal In Sidebar

`ScrollViewReader.scrollTo` can still work, but scroll IDs must be explicit:

- repository container: `SidebarScrollID.repository(repositoryID)`
- worktree row: `SidebarScrollID.worktree(worktreeID)`
- archived worktrees row: `SidebarScrollID.archivedWorktrees`

When revealing a collapsed worktree:

1. expand its repository
2. wait for an event-driven row availability signal
3. scroll to `SidebarScrollID.worktree(worktreeID)`
4. consume pending reveal

Do not rely on a fixed number of `Task.yield()` calls in the new architecture. The implementation can use a scroll target registry, preference key, or equivalent view materialization signal.

### Accessibility

Minimum accessibility requirements:

- repository headers expose button/row labels and expanded state
- worktree rows expose selection state
- drag handles or rows expose reorder affordance where AppKit/SwiftUI can support it
- Canvas / Shelf / Archived rows keep meaningful labels

If full native `List` accessibility cannot be matched in V1, document the gap and keep keyboard command coverage strong.

## Implementation Plan

### Phase 0: Baseline and Guardrails

- Add a short manual repro checklist for:
  - repository drag up/down over expanded target
  - bulk expand/collapse with many repositories
  - worktree reorder in pinned/unpinned groups
  - sidebar multi-selection
  - reveal-in-sidebar
- Add signposts around sidebar presentation build and drag state transitions if trace work is needed.
- Establish `LazyVStack` vs `VStack` decision metrics before replacing the list:
  - expand/collapse latency for 10+ repositories
  - frame stability during repository drag
  - CPU peak during drag and bulk expand/collapse
  - body recomputation count for repository container and worktree row views
- Keep current `List` code untouched until M1 and presentation tests exist.

### M1: Stabilize Old `List` Drag Behavior

Files likely involved:

- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeOrdering.swift`
- `supacode/Features/Repositories/Views/SidebarListView.swift`
- `supacodeTests/RepositoriesFeatureTests.swift`

Deliver:

- reducer-level sidebar drag state
- view action for drag begin/end from the old `List` path
- delayed or no-animation handling for notification-driven reorder during drag
- deterministic pending reorder flush on drag end

Tests:

- notification during sidebar drag does not mutate visible worktree order immediately
- drag end applies the pending notification reorder in deterministic order
- multiple notifications during one drag produce stable ordering
- stale pending worktree IDs are ignored
- `moveNotifiedWorktreeToTop == false` remains a no-op
- persistence is called only when the reorder is actually applied

### Phase 1: Pure Presentation and Reorder Mapping

Files likely involved:

- `supacode/Features/Repositories/Models/SidebarPresentation.swift` (new)
- `supacodeTests/SidebarPresentationTests.swift` (new)
- existing reducer ordering tests

Deliver:

- pure sidebar presentation builder
- stable scroll IDs
- pure drop-destination mapping for repository and worktree reorder
- one unified presentation path for empty and non-empty ordered roots
- explicit failed repository row reorder semantics

Tests:

- expanded repository keeps one outer item with child rows
- failed repositories preserve the chosen reorder semantics
- plain folders produce repository containers with no worktree children
- pinned/main/pending/unpinned sections are preserved
- empty ordered roots and custom ordered roots produce equivalent presentation rules
- repository drop destinations map to expected order
- worktree drop destinations map within pinned/unpinned sections

### Phase 2: New Container Views Behind a Switch

Files likely involved:

- `SidebarListView.swift`
- `RepositorySectionView.swift`
- `WorktreeRowsView.swift`
- new `SidebarContainerListView.swift`
- new `RepositoryContainerRow.swift`

Deliver:

- render the new container sidebar behind a local compile-time or private runtime switch
- no reducer changes except new presentation helpers if needed
- preserve row styling visually before enabling custom drag/drop
- preserve root-level URL drop for files dragged into blank sidebar space
- preserve context menus and drag previews

This phase should be screenshot/manual verified before deleting the old `List` path.

### Phase 3: Explicit Selection, Focus, and Reveal

Deliver:

- click handling for repository and worktree rows
- explicit selection visuals
- multi-selection behavior matching the compatibility matrix
- `sidebarSelections -> setSidebarSelectedWorktreeIDs` synchronization
- focused actions and hotkey row values
- reveal-in-sidebar via new scroll IDs and row availability events
- focused terminal handoff after single worktree selection

Tests:

- pure selection helper tests
- reducer tests for sidebar selected worktree synchronization
- focused action manual checklist for confirm/archive/delete and numbered hotkeys

### Phase 4: Custom Repository Reorder

Deliver:

- repository drag payload
- custom repo-level insertion indicator
- drop handling that dispatches repository reorder through the existing persistence path
- drag-time UI freeze for non-essential row affordances

Manual verification:

- dragging a repository upward shows indicator below the target repository container when appropriate
- dragging a repository downward never shows the indicator between target header and target worktree rows
- failed repository rows follow the documented reorder semantics

### Phase 5: Custom Worktree Reorder

Deliver:

- pinned/unpinned scoped worktree drop zones
- custom worktree insertion indicator
- main/pending rows stay non-movable
- existing persistence paths remain unchanged

Manual verification:

- pinned worktree reorder persists
- unpinned worktree reorder persists
- dragging over main/pending rows does not create invalid moves

### Phase 6: Remove Old `List` Path and Polish

Deliver:

- delete old `List(selection:)` implementation
- remove obsolete `RepositorySectionView` / `WorktreeRowsView` pieces or fold them into new components
- final accessibility pass
- final animation pass for bulk expand/collapse
- update issue #249 with final implementation notes

## Verification Matrix

Automated:

- `SidebarPresentationTests`
- reducer tests for sidebar drag gate and notification reorder concurrency
- reducer tests for expanded/collapsed state write-back and invalid collapsed ID cleanup
- reducer tests for sidebar selected worktree synchronization
- existing `RepositoriesFeatureTests` ordering tests
- existing `RepositorySectionViewTests` migrated or renamed
- `make check`
- `make build-app`

Manual:

1. Select a plain folder repository row.
2. Click a git repository header and confirm it expands/collapses without selecting a worktree.
3. Select a git repository worktree row and confirm terminal focus.
4. Cmd-click multiple worktree rows and confirm bulk archive/delete commands still target selected rows.
5. Verify confirm/archive/delete menu commands target the same worktrees as before.
6. Verify numbered worktree hotkeys use visible sidebar rows.
7. Expand/collapse one repository.
8. Bulk expand/collapse at least 10 repositories.
9. Drag repository upward and downward across expanded repositories.
10. Drag pinned worktrees within a repository.
11. Drag unpinned worktrees within a repository.
12. Trigger reveal-in-sidebar from Canvas or command.
13. Verify Canvas / Shelf / Archived interactions remain correct.
14. Verify notification/task/run-script indicators update without moving rows during a drag.
15. Drop a repository URL onto a visible row and onto blank sidebar space.
16. Verify repository and worktree context menus.
17. Verify drag previews.
18. Verify worktree rows do not gain type-select behavior in V1.

## Risks

### Native `List` behavior loss

Risk: custom scroll rows may lose some free AppKit sidebar behavior.

Mitigation:

- preserve command-based navigation first
- add explicit accessibility labels/traits
- keep manual keyboard/accessibility checklist

### Reorder implementation complexity

Risk: custom drag/drop can become more complex than native `.onMove`.

Mitigation:

- keep pure drop-index mapping tested
- keep repository reorder and worktree reorder separate
- defer cross-repository worktree moves

### UI regressions from broad rewrite

Risk: replacing the sidebar in one PR touches selection, animation, and drag.

Mitigation:

- stage behind a private switch until visual behavior is verified
- land M1 and presentation model tests first
- keep reducer actions and persistence shape stable

### Performance regressions

Risk: replacing lazy `List` with `VStack` could render too much.

Mitigation:

- start with `LazyVStack`
- switch only repository containers to non-lazy child stacks if expand/collapse animation needs it
- decide using the Phase 0 metrics rather than visual impression alone

## Recommendation

Proceed with Option B as the #249 plan: a custom `ScrollView` sidebar with repository containers as outer items.

Do not attempt to fix the repository insertion indicator through reducer index changes. The indicator is a symptom of the current `List` row structure, not the persisted ordering logic.

The safest execution path is:

1. baseline metrics and manual guardrails
2. M1 old `List` drag gate and reducer concurrency tests
3. pure presentation model and tests
4. render-only new sidebar path
5. explicit selection, focus, and reveal
6. custom repository reorder
7. custom worktree reorder
8. remove old `List` path

This is larger than a tactical #222 fix, but it addresses the underlying sidebar design mismatch and gives future sidebar features a cleaner foundation.
