# Remote SSH Management + tmux Auto-Detect Design (Prowl)

Date: 2026-03-27  
Status: Approved for planning

## 1. Goal

Add first-class remote repository support to Prowl with:

- shared, persisted SSH host profiles reusable across many repositories
- repository-level remote path and tmux session management
- native SSH/tmux/git command execution for remote workflows
- tmux session discovery and user-driven attach behavior
- mosh-like reconnect continuity over SSH (no mosh transport)

This design follows the existing Prowl architecture (`TCA + WorktreeTerminalManager + Ghostty`) and does not replace Ghostty terminal rendering.

## 2. Product Decisions (Locked)

1. Shared host profiles are required because one machine can host many repos.
2. SSH connection data is shared/persisted globally; repo path and tmux session are repo-level.
3. Native `ssh` and `tmux` commands are preferred.
4. On remote open/attach, tmux session selection is always explicit via picker.
5. No mosh protocol in v1. Reconnect UX should be mosh-like, but SSH transport only.
6. Remote git/worktree operations are in scope in v1 and execute over SSH.
7. Remote add flow is a single flow:
   - user chooses `Add Remote Repository`
   - flow prompts for host creation first
   - then prompts for repo path and validation
8. Auth support in v1:
   - SSH key/agent
   - optional password fallback stored in macOS Keychain
9. SSHFS is optional and non-core in v1 (SSH command execution is primary mode).

## 3. Non-Goals (v1)

- mosh UDP transport support
- full host-profile marketplace/import/export
- SSH jump-host presets and advanced proxy presets in initial release
- SSHFS as required path for remote operations
- changing existing local-only behavior unless repository location is remote

## 4. Architecture

### 4.1 New Domain Models

Add global host profile model:

- `SSHHostProfile`
  - `id`
  - `displayName`
  - `host`
  - `user`
  - `port`
  - `authMethod` (`publicKey`, `password`)
  - `createdAt`, `updatedAt`
  - keychain lookup key (or stable key derivation input)

Add repository location model:

- `RepositoryExecutionLocation`
  - `.local`
  - `.remote(hostProfileID: SSHHostProfile.ID, remoteRepositoryPath: String)`

Add repo-level remote terminal defaults:

- `defaultTmuxSessionName: String?`
- `lastAttachedTmuxSessionName: String?`

### 4.2 Persistence Boundaries

- Host profiles: global persisted settings.
- Remote passwords: Keychain only, never plain-text in repo settings or logs.
- Repository remote binding (location/path/session defaults): per-repository settings.

### 4.3 Execution Abstraction

Introduce a single endpoint-aware execution seam used by remote-capable operations:

- Local repository -> current local process execution.
- Remote repository -> native `/usr/bin/ssh` invocation with:
  - connect timeout
  - keepalive options
  - bounded execution timeout
  - stable control socket naming

Execution interfaces remain command-oriented and avoid introducing protocol-specific runtime complexity.

## 5. UX and Data Flow

### 5.1 Add Remote Repository (Single Flow)

1. User chooses `Add Repository` -> `Remote Repository`.
2. Flow requires host creation step first (v1).
3. User enters remote repository path.
4. App validates over SSH:
   - host connect/auth
   - path existence/access
   - `tmux` availability
   - git repository and worktree capability checks
5. App persists:
   - shared `SSHHostProfile`
   - repository remote binding (`hostProfileID + remoteRepositoryPath`)

Future extension (explicitly planned): step 2 can become `Select existing host profile` or `Add new`.

### 5.2 Terminal Open / tmux Attach

When opening a remote repository/worktree:

1. Query tmux sessions via SSH (`tmux list-sessions`).
2. Always show session picker when sessions are available.
3. Picker options:
   - `Attach Existing Session`
   - `Create New Managed Session`
4. Persist selection into repo-level fields (`lastAttachedTmuxSessionName`, optional default).
5. Attach terminal using SSH + tmux command path.

### 5.3 Remote Git/Worktree Operations

Existing repository actions should preserve behavior semantics while switching execution backend:

- `git worktree list`
- `git worktree add`
- `git worktree remove`
- related branch/worktree operations

For remote repositories, commands execute on host via SSH at repo path.
In v1, adding a remote repository requires the remote path to be a git repository.

### 5.4 Reconnect UX (SSH Only)

If remote terminal process exits unexpectedly:

1. Move to `Reconnecting...` state.
2. Retry attach with bounded exponential backoff.
3. Reattach selected tmux session when available.
4. If reattach cannot complete, present user actions:
   - `Retry`
   - `Choose Session`
   - `Update Credentials`

No implicit destructive reset of repo/session bindings on transient failure.

## 6. Command and Runtime Behavior

### 6.1 SSH Command Construction

Remote command execution should:

- use `/usr/bin/ssh`
- include keepalive/connect timeout options
- use explicit target (`[user@]host`, optional `-p`)
- execute escaped remote command payloads
- enforce operation-level timeout

### 6.2 tmux Session Metadata

When creating managed sessions, write tmux user options for later discovery and disambiguation:

- repository identity key
- repository path
- app-managed marker

This prevents collisions and improves picker defaults without requiring hidden session auto-attach.

### 6.3 Logging

All runtime logs must use `SupaLogger`.
Sensitive values (passwords, raw secrets, keychain payloads) must never appear in logs.

## 7. Error Handling

### 7.1 Error Classes

Surface user-facing errors by phase:

- host unreachable / DNS
- authentication failure
- timeout
- host key mismatch
- tmux unavailable
- git/worktree command failure

Each error should include operation context and actionable next step.

### 7.2 Profile Lifecycle Safety

- Deleting a host profile in use should be blocked by default.
- User must reassign affected repositories or confirm detach flow.
- Password updates should support immediate retry without re-adding repository.

### 7.3 Session Attach Safety

- If selected tmux session disappears between selection and attach, reprompt with refreshed list.
- If no sessions exist, user can create managed session directly from the attach flow.

## 8. Testing Strategy

### 8.1 Unit Tests

- Host profile model and normalization
- Host input parsing (`[user@]host[:port]`)
- Keychain persistence and credential update/read paths
- Endpoint-aware command runner (local vs remote command construction)
- SSH option filtering and timeout behavior
- tmux session parsing
- remote git/worktree command composition

### 8.2 Reducer / State Tests (TCA)

- remote add flow state machine
- host-first add flow transitions and validation failures
- session picker presentation and selection persistence
- reconnect state transitions
- in-use host profile deletion guard behavior

### 8.3 Integration Tests (Stubbed Process Runner)

- end-to-end remote repository open -> session picker -> attach
- remote git worktree operations routed through SSH command runner
- credential update and retry success path

### 8.4 Manual QA Matrix

- SSH key success/failure
- password keychain update/retry
- unreachable host / timeout / host key mismatch
- tmux missing vs no sessions vs multiple sessions
- remote reconnect under transient disconnect
- remote git worktree create/list/remove behavior

## 9. Rollout Plan

### Phase 1: Internal

- behind feature flag
- limited dogfooding with real remote hosts
- collect error-class distribution and reconnect stability

### Phase 2: Public Beta

- enable by default for fork users
- keep diagnostics and fallback controls enabled

### Phase 3: Stable

- remove flag
- keep rollback switch to disable remote execution path rapidly if needed

## 10. Implementation Notes for Planning

- Prefer incremental slices:
  1. models + persistence + host-first remote add flow
  2. endpoint-aware command execution
  3. tmux session picker + attach
  4. remote git/worktree operation routing
  5. reconnect state/polish + QA hardening
- Preserve existing local behavior as invariant.
- Keep module boundaries explicit to avoid remote-specific logic leaking across unrelated reducers.

## 11. References

- Mori PR #19 (remote SSH project support and tmux attach patterns):  
  https://github.com/vaayne/mori/pull/19
- Mosh project (continuity/reconnect UX inspiration; transport not adopted):  
  https://mosh.org/
