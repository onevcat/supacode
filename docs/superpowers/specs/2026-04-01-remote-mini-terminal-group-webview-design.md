# Remote Mini-Terminal Group Integration Design

## Background
Prowl currently focuses on local Ghostty-based terminal orchestration per worktree. The new requirement is to let Prowl directly control and display remote mini-terminal(tmux) sessions inside the app.

Confirmed constraints:
- Use WebView embedding (not native terminal protocol implementation).
- Add a left sidebar block parallel to `Repositories`.
- Support multiple remote base URLs.
- Group discovery must match mini-terminal frontend logic exactly.
- Keep click-only icon entry (remove text label style from add entry).
- No native auth handling in Prowl for now; H5 + Nginx handle auth.

## Goals
- Surface remote tmux groups in Prowl sidebar with a clear navigation model.
- Open selected remote group directly inside Prowl detail area.
- Auto-discover existing groups from remote mini-terminal services.
- Minimize coupling: remote behavior remains owned by mini-terminal frontend.

## Non-Goals
- Reimplementing terminal rendering/protocol in Swift.
- Managing remote auth tokens/cookies in native code.
- Deleting remote tmux sessions from Prowl in MVP.
- Changing local Ghostty terminal behavior.

## Discovery Rules (Must Match mini-terminal)
Group discovery must be identical to mini-terminal frontend (`multi-tmux/index.js`, `model.mjs`):

1. Request sessions from:
- `GET <remoteBaseURL>/api/v1/terminal/sessions?scope=multi-tmux`

2. Parse group only from `reuseKey`:
- accept only keys with prefix `multi-tmux:`
- parse group as first segment after prefix before next `:`
- ignore sessions where group cannot be parsed

3. Do not infer group from `cwd`.

This keeps Prowl and mini-terminal grouping semantics consistent and avoids drift.

## High-Level Architecture

### New Feature: `RemoteGroupsFeature`
A dedicated TCA feature handles:
- remote endpoint registry
- fetched remote sessions
- derived groups per endpoint
- selected remote group target
- loading/error states per endpoint/group

### Existing Feature Boundaries
- `RepositoriesFeature` stays responsible for local repos/worktrees.
- `WorktreeTerminalManager` remains local Ghostty runtime manager.
- New remote feature does not mutate Ghostty state.

### View Layer
- Sidebar adds a new section: `Remote Groups` (parallel to `Repositories`).
- Detail pane adds a remote branch:
- if local worktree selected: existing detail behavior
- if remote group selected: show `RemoteGroupDetailView` with `WKWebView`

## Data Model

### `RemoteEndpoint`
- `id: UUID`
- `baseURL: String` (normalized, e.g. `https://host/mini-terminal/`)
- `createdAt`, `updatedAt`

### `RemoteGroupRef`
- `endpointID: UUID`
- `group: String`
- `sessionCount: Int`
- `lastActiveAt: Date?`
- `sampleCWD: String?`

### `RemoteSelection`
- `.none`
- `.group(endpointID: UUID, group: String)`
- `.overview(endpointID: UUID)`

### Persistence
Persist endpoint list and last remote selection in app storage (`@Shared`-backed settings state).

## URL Strategy

Given an endpoint base URL:
- overview URL: `<baseURL>`
- group URL: `<baseURL>?group=<slug>`

Example:
- endpoint: `https://cybernotes.mistj.com:9444/mini-terminal/`
- group page: `https://cybernotes.mistj.com:9444/mini-terminal/?group=alpha`

## UX and Interaction

### Sidebar Structure
- Repositories (existing)
- Remote Groups (new)

Inside Remote Groups:
- endpoint nodes
- under each endpoint, discovered group items
- optional endpoint overview row

### Add Entry (Icon-Only)
- Replace text-style add entry with icon-only click target.
- Click opens modal/sheet:
- `Remote URL` (required)
- optional initial `Group`

Behavior after submit:
- URL only: add endpoint, open endpoint overview in detail.
- URL + group: add endpoint, select that group and open group URL.
- No session auto-creation.

### Detail Area
`RemoteGroupDetailView` uses `WKWebView`:
- loads target URL
- supports reload action
- shows inline failure state if load fails

## Error Handling
- Endpoint fetch failure: mark endpoint as failed; keep entry visible.
- Group page load failure: show recoverable view with `Retry` and `Edit URL`.
- Invalid URL input: block save with explicit validation message.

No destructive automatic cleanup on failures.

## State and Event Flow
1. User adds endpoint via icon action.
2. `RemoteGroupsFeature` validates + stores endpoint.
3. Feature triggers sessions fetch for endpoint.
4. Sessions are grouped using reuseKey parser.
5. Sidebar renders discovered groups.
6. User selects group.
7. Detail pane loads `WKWebView` with `?group=` URL.

## Testing Strategy

### Unit Tests
- URL normalization and group URL generation.
- `reuseKey` parser parity tests against expected `multi-tmux:` forms.
- session-to-group aggregation behavior.
- endpoint failure and retry state transitions.

### Integration/View Tests
- selecting remote group changes detail branch to WebView state.
- invalid endpoint input shows validation error.
- icon-only add action still reachable and triggers modal.

## Migration and Rollout
- Ship behind default-on behavior (no feature flag initially).
- Keep all local terminal paths untouched.
- If remote endpoints are empty, Remote Groups section shows empty-state guidance.

## Risks
- WebView lifecycle edge cases (reload loops, stale navigation state).
- Remote schema drift if mini-terminal API changes.

Mitigation:
- strict parser tests for reuseKey rules.
- defensive response parsing and error surfacing.

## Open Questions (Resolved in This Spec)
- Group discovery source: `reuseKey` only (resolved).
- Auth handling: native does not handle auth (resolved).
- Session creation on add: do not auto-create (resolved).
