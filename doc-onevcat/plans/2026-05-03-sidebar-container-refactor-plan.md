# Sidebar Container Refactor Plan

Status: planning
Issue: [#249](https://github.com/onevcat/Prowl/issues/249)
Related: [#222](https://github.com/onevcat/Prowl/issues/222)

## Goal

Refactor the repository sidebar so each repository behaves as one stable visual and drag unit, while worktrees remain selectable, reorderable, and efficient to update.

This should fix the structural mismatch where the app treats repositories as reorderable units but SwiftUI `List` sees repository headers and worktree rows as separate rows. That mismatch shows up as:

- incorrect repository drag insertion indicators when dragging downward across expanded repositories
- unstable bulk expand/collapse animations
- potential sidebar flicker during drag when live terminal / notification / ordering updates arrive

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

- special rows: Canvas, Shelf, archived worktrees, repository list header
- repository row selection for plain folders
- worktree multi-selection
- repository expand/collapse
- native repository reorder
- native worktree reorder for pinned and unpinned groups
- reveal-in-sidebar via `ScrollViewReader.scrollTo`
- native sidebar styling and accessibility

This makes local fixes brittle because changing row structure affects selection, drag, animation, and scroll identity at the same time.

### 3. Live state still reaches rows during drag

Some expensive state reads have already been isolated, such as moving repository tab-count reads into `RepoHeaderTabCountBadge`.

Remaining drag-time churn sources include:

- `WorktreeRowsView` animates changes to `rowIDs`
- each worktree row reads terminal notification/task/run-script state
- notification-driven reorder can call `withAnimation(.snappy)` and mutate `worktreeOrderByRepository`
- row hover/action UI changes while a drag session is active

These are not necessarily the root cause of the drop-indicator bug, but they are credible contributors to #222-style flicker.

## Recommended Direction

Use a custom sidebar scroll container rather than trying to keep the current flat `List` structure.

Recommended shape:

```text
ScrollViewReader
└── ScrollView
    └── LazyVStack or VStack
        ├── Special rows
        ├── RepositoryContainerRow
        │   ├── RepositoryHeaderRow
        │   └── WorktreeRows
        └── FailedRepositoryRow
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

This is the recommended route for #249 if the goal is "fix the sidebar design once" rather than patch one symptom.

### Option C: Short-term drag-time freeze only

Pros:

- small
- may help #222 flicker

Cons:

- does not fix repository insertion indicator because row boundaries remain wrong
- leaves the main structural mismatch in place

This can be kept as a subset of Option B, but it is not enough alone.

## Proposed Architecture

### SidebarPresentationModel

Introduce a pure presentation model that flattens current repository state into explicit sidebar units.

Suggested model:

```swift
struct SidebarPresentation: Equatable {
  var items: [SidebarItem]
}

enum SidebarItem: Equatable, Identifiable {
  case listHeader(SidebarListHeaderModel)
  case special(SidebarSpecialRowModel)
  case repository(SidebarRepositoryContainerModel)
  case failedRepository(FailedRepositoryModel)
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

- outer `items` contains one item per repository, not one item per row
- worktree sections remain inside the repository container
- presentation construction should be pure and unit-tested
- live terminal state should not be part of the broad presentation model unless required for layout identity

### Selection

Replace `List(selection:)` with explicit selection handling.

Keep `RepositoriesFeature.State.selection` and `sidebarSelectedWorktreeIDs` as the source of truth, but route clicks through helper functions:

- repository header click:
  - plain folder: select repository
  - git repository: toggle expand by default, or select repository if a future repository-detail mode needs it
- worktree row click:
  - normal click: select worktree and focus terminal
  - Cmd-click: toggle multi-selection
  - Shift-click: optional follow-up, only if current behavior supports it through `List`
- Canvas / Shelf / Archived rows: dispatch existing actions

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
- sidebar focus does not accidentally forward text while Canvas / Shelf rules say it should not

### Repository Reorder

Replace `ForEach(...).onMove` with explicit repository drag/drop.

Suggested approach:

- make `RepositoryContainerRow` draggable with repository ID payload
- render a custom repository insertion indicator between repository containers
- compute drop destination as a repository index
- dispatch existing `.worktreeOrdering(.repositoriesMoved(offsets, destination))` or a new clearer action such as `.repositoriesReordered([Repository.ID])`

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

Add a small sidebar drag state to suppress non-essential row churn.

During any sidebar drag:

- freeze hover-only row actions
- hide pull request / notification popover affordances that resize rows
- suppress row-ID animations caused by notification-driven reorder
- defer "move notified worktree to top" until drag ends, or apply it without animation after drop

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
- special rows: `SidebarScrollID.canvas`, etc.

When revealing a collapsed worktree:

1. expand its repository
2. yield for layout materialization
3. scroll to `SidebarScrollID.worktree(worktreeID)`
4. consume pending reveal

This matches the current two-yield approach but removes dependency on `List` row materialization.

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
- Keep current `List` code untouched until presentation tests exist.

### Phase 1: Pure Presentation and Reorder Mapping

Files likely involved:

- `supacode/Features/Repositories/Models/SidebarPresentation.swift` (new)
- `supacodeTests/SidebarPresentationTests.swift` (new)
- existing reducer ordering tests

Deliver:

- pure sidebar presentation builder
- stable scroll IDs
- pure drop-destination mapping for repository and worktree reorder
- tests for:
  - expanded repository keeps one outer item with child rows
  - failed repositories preserve order
  - plain folders produce repository containers with no worktree children
  - pinned/main/pending/unpinned sections are preserved
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

This phase should be screenshot/manual verified before deleting the old `List` path.

### Phase 3: Explicit Selection and Reveal

Deliver:

- click handling for repository and worktree rows
- explicit selection visuals
- multi-selection behavior matching current sidebar expectations
- reveal-in-sidebar via new scroll IDs
- focused terminal handoff after single worktree selection

Tests:

- pure selection helper tests if logic is factored out
- existing reducer selection tests should keep passing

### Phase 4: Custom Repository Reorder

Deliver:

- repository drag payload
- custom repo-level insertion indicator
- drop handling that dispatches repository reorder
- drag-time UI freeze for non-essential row affordances

Manual verification:

- dragging a repository upward shows indicator below the target repository container when appropriate
- dragging a repository downward never shows the indicator between target header and target worktree rows
- failed repository rows either reorder correctly or are explicitly non-reorderable

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
- existing `RepositoriesFeatureTests` ordering tests
- existing `RepositorySectionViewTests` migrated or renamed
- `make check`
- `make build-app`

Manual:

1. Select a plain folder repository row.
2. Select a git repository worktree row and confirm terminal focus.
3. Cmd-click multiple worktree rows and confirm bulk archive/delete commands still target selected rows.
4. Expand/collapse one repository.
5. Bulk expand/collapse at least 10 repositories.
6. Drag repository upward and downward across expanded repositories.
7. Drag pinned worktrees within a repository.
8. Drag unpinned worktrees within a repository.
9. Trigger reveal-in-sidebar from Canvas or command.
10. Verify Canvas / Shelf / Archived rows remain selectable.
11. Verify notification/task/run-script indicators update without moving rows during a drag.

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
- land presentation model tests first
- keep reducer actions and persistence shape stable

### Performance regressions

Risk: replacing lazy `List` with `VStack` could render too much.

Mitigation:

- start with `LazyVStack`
- switch only repository containers to non-lazy child stacks if expand/collapse animation needs it
- measure with the existing signpost / Instruments workflow if the sidebar feels worse

## Recommendation

Proceed with Option B as the #249 plan: a custom `ScrollView` sidebar with repository containers as outer items.

Do not attempt to fix the repository insertion indicator through reducer index changes. The indicator is a symptom of the current `List` row structure, not the persisted ordering logic.

The safest execution path is:

1. pure presentation model and tests
2. render-only new sidebar path
3. explicit selection/reveal
4. custom repository reorder
5. custom worktree reorder
6. remove old `List` path

This is larger than a tactical #222 fix, but it addresses the underlying sidebar design mismatch and gives future sidebar features a cleaner foundation.
