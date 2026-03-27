# Remote SSH + tmux Auto-Detect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship remote repository support with shared SSH host profiles, repo-level remote path/tmux binding, always-on tmux session picker, SSH-only reconnect continuity, and remote git worktree operations.

**Architecture:** Keep Prowl's existing TCA + terminal architecture, add endpoint-aware execution context, and layer remote support into existing repository/worktree flows rather than branching into a separate app path. Persist shared hosts globally, persist repo remote bindings per repository, and execute remote git/tmux through native `ssh` commands with strict timeouts and keychain-backed password fallback.

**Tech Stack:** Swift 6.2, TCA, Sharing (`@Shared` / `SharedKey`), GhosttyKit, `Process`, macOS Security/Keychain APIs, Swift Testing.

---

## Scope Check

The spec includes multiple subsystems (host profiles, remote add flow, command execution, session picker, reconnect), but they are one coherent vertical feature. This plan keeps them in a single implementation track while isolating each subsystem into explicit tasks and commits.

## File Structure (Lock Before Coding)

### New files

- `supacode/Domain/SSHHostProfile.swift`
  - Shared host model and auth method enum.
- `supacode/Domain/RepositoryEndpoint.swift`
  - Local vs remote endpoint metadata (`profileID + remotePath`).
- `supacode/Clients/Security/KeychainClient.swift`
  - Keychain save/load/delete for SSH passwords.
- `supacode/Infrastructure/SSH/SSHCommandSupport.swift`
  - SSH option composition, shell escaping, control-socket path hashing, askpass helpers.
- `supacode/Clients/Remote/RemoteExecutionClient.swift`
  - Executes remote commands over SSH with timeout/retry contracts.
- `supacode/Clients/Remote/RemoteTmuxClient.swift`
  - Remote tmux session listing/attach/create helpers.
- `supacode/Features/Repositories/Reducer/RemoteConnectFeature.swift`
  - Host-first remote repository add flow state machine.
- `supacode/Features/Repositories/Views/RemoteConnectSheet.swift`
  - SwiftUI sheet for remote add flow.
- `supacode/Features/Repositories/Reducer/RemoteSessionPickerFeature.swift`
  - Session picker reducer (`always show picker` behavior).
- `supacode/Features/Repositories/Views/RemoteSessionPickerSheet.swift`
  - Session picker view.
- `supacode/Features/Settings/Reducer/SSHHostsFeature.swift`
  - Host profile CRUD reducer.
- `supacode/Features/Settings/Views/SSHHostsSettingsView.swift`
  - Host profile management UI section.
- `supacodeTests/SSHCommandSupportTests.swift`
- `supacodeTests/KeychainClientTests.swift`
- `supacodeTests/RemoteExecutionClientTests.swift`
- `supacodeTests/RemoteTmuxClientTests.swift`
- `supacodeTests/RemoteConnectFeatureTests.swift`
- `supacodeTests/RemoteSessionPickerFeatureTests.swift`
- `supacodeTests/GitClientRemoteCommandTests.swift`
- `supacodeTests/SettingsFeatureSSHHostsTests.swift`

### Modified files

- `supacode/Domain/PersistedRepositoryEntry.swift`
- `supacode/Domain/Repository.swift`
- `supacode/Domain/Worktree.swift`
- `supacode/Features/Settings/Models/SettingsFile.swift`
- `supacode/Features/Settings/Models/RepositorySettings.swift`
- `supacode/Features/Settings/BusinessLogic/RepositoryPersistenceKeys.swift`
- `supacode/Support/SupacodePaths.swift`
- `supacode/Clients/Repositories/RepositoryPersistenceClient.swift`
- `supacode/Clients/Repositories/GitClientDependency.swift`
- `supacode/Clients/Git/GitClient.swift`
- `supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift`
- `supacode/Features/Settings/Views/RepositorySettingsView.swift`
- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- `supacode/App/ContentView.swift`
- `supacode/Features/Repositories/Views/SidebarFooterView.swift`
- `supacode/Features/Settings/Views/SettingsSection.swift`
- `supacode/Features/Settings/Views/SettingsView.swift`
- `supacode/Features/Settings/Reducer/SettingsFeature.swift`
- `supacode/Features/CommandPalette/CommandPaletteItem.swift`
- `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift`
- `supacode/Features/App/Reducer/AppFeature.swift`
- `supacode/Clients/Terminal/TerminalClient.swift`
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- `supacodeTests/SettingsFilePersistenceTests.swift`
- `supacodeTests/RepositoryPersistenceClientTests.swift`
- `supacodeTests/RepositorySettingsFeatureTests.swift`
- `supacodeTests/RepositoriesFeatureTests.swift`
- `supacodeTests/CommandPaletteFeatureTests.swift`
- `supacodeTests/AppFeatureCommandPaletteTests.swift`

## Task 1: Create Isolated Worktree + Baseline Safety Check

**Files:**
- Modify: none
- Test: none

- [ ] **Step 1: Create dedicated git worktree and feature branch**

```bash
git worktree add ../Prowl-remote-ssh -b feature/remote-ssh-tmux
```

- [ ] **Step 2: Enter new worktree and confirm branch**

Run: `cd ../Prowl-remote-ssh && git branch --show-current`  
Expected: `feature/remote-ssh-tmux`

- [ ] **Step 3: Capture clean baseline before edits**

Run: `git status --short`  
Expected: empty output

- [ ] **Step 4: Run a fast baseline test target**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SettingsFilePersistenceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: PASS

- [ ] **Step 5: Commit setup note (optional)**

No commit for this task (code unchanged).

## Task 2: Add Core Remote Domain Models + Persistence Schema

**Files:**
- Create: `supacode/Domain/SSHHostProfile.swift`
- Create: `supacode/Domain/RepositoryEndpoint.swift`
- Modify: `supacode/Domain/PersistedRepositoryEntry.swift`
- Modify: `supacode/Domain/Repository.swift`
- Modify: `supacode/Domain/Worktree.swift`
- Modify: `supacode/Features/Settings/Models/SettingsFile.swift`
- Test: `supacodeTests/SettingsFilePersistenceTests.swift`
- Test: `supacodeTests/RepositoryPersistenceClientTests.swift`

- [ ] **Step 1: Write failing tests for backward-compatible decode**

```swift
@Test(.dependencies) func settingsFileDecodesWithoutSSHHostsKey() throws {
  let legacyJSON = #"{"global":{"appearanceMode":"dark","updatesAutomaticallyCheckForUpdates":true,"updatesAutomaticallyDownloadUpdates":false},"repositories":{},"repositoryRoots":[]}"#
  let data = Data(legacyJSON.utf8)
  let decoded = try JSONDecoder().decode(SettingsFile.self, from: data)
  #expect(decoded.sshHostProfiles.isEmpty)
}

@Test func persistedRepositoryEntryDecodesLegacyLocalFormat() throws {
  let legacy = #"{"path":"/tmp/repo","kind":"git"}"#
  let decoded = try JSONDecoder().decode(PersistedRepositoryEntry.self, from: Data(legacy.utf8))
  #expect(decoded.endpoint == .local)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SettingsFilePersistenceTests \
  -only-testing:supacodeTests/RepositoryPersistenceClientTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: compile/test failure for missing `sshHostProfiles` and `endpoint`.

- [ ] **Step 3: Implement domain/persistence types**

```swift
// supacode/Domain/SSHHostProfile.swift
nonisolated struct SSHHostProfile: Codable, Equatable, Sendable, Identifiable {
  enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case publicKey
    case password
  }
  let id: String
  var name: String
  var host: String
  var user: String?
  var port: Int?
  var authMethod: AuthMethod
}

// supacode/Domain/RepositoryEndpoint.swift
nonisolated enum RepositoryEndpoint: Codable, Equatable, Sendable {
  case local
  case remote(hostProfileID: String, remotePath: String)
}
```

```swift
// supacode/Domain/PersistedRepositoryEntry.swift
nonisolated struct PersistedRepositoryEntry: Codable, Equatable, Sendable {
  let path: String
  let kind: Repository.Kind
  var endpoint: RepositoryEndpoint

  init(path: String, kind: Repository.Kind, endpoint: RepositoryEndpoint = .local) {
    self.path = path
    self.kind = kind
    self.endpoint = endpoint
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    path = try c.decode(String.self, forKey: .path)
    kind = try c.decode(Repository.Kind.self, forKey: .kind)
    endpoint = try c.decodeIfPresent(RepositoryEndpoint.self, forKey: .endpoint) ?? .local
  }
}
```

```swift
// supacode/Features/Settings/Models/SettingsFile.swift (new field + migration default)
var sshHostProfiles: [SSHHostProfile]
```

- [ ] **Step 4: Run the targeted tests and verify pass**

Run same command from Step 2.  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  supacode/Domain/SSHHostProfile.swift \
  supacode/Domain/RepositoryEndpoint.swift \
  supacode/Domain/PersistedRepositoryEntry.swift \
  supacode/Domain/Repository.swift \
  supacode/Domain/Worktree.swift \
  supacode/Features/Settings/Models/SettingsFile.swift \
  supacodeTests/SettingsFilePersistenceTests.swift \
  supacodeTests/RepositoryPersistenceClientTests.swift
git commit -m "feat: add remote endpoint domain and settings schema"
```

## Task 3: Add Keychain Client + SSH Utility Primitives

**Files:**
- Create: `supacode/Clients/Security/KeychainClient.swift`
- Create: `supacode/Infrastructure/SSH/SSHCommandSupport.swift`
- Modify: `supacode/Features/Settings/Models/RepositorySettings.swift`
- Test: `supacodeTests/KeychainClientTests.swift`
- Test: `supacodeTests/SSHCommandSupportTests.swift`

- [ ] **Step 1: Write failing tests for control path hashing and option filtering**

```swift
@Test func controlSocketPathFallsBackToTmpWhenTooLong() {
  let path = SSHCommandSupport.controlSocketPath(endpointKey: String(repeating: "x", count: 512))
  #expect(path.hasPrefix("/tmp/") || path.contains("/.prowl/"))
}

@Test func removingBatchModeStripsOnlyBatchModePairs() {
  let filtered = SSHCommandSupport.removingBatchMode(from: ["-o","BatchMode=yes","-o","ConnectTimeout=8"])
  #expect(filtered == ["-o","ConnectTimeout=8"])
}
```

- [ ] **Step 2: Write failing tests for keychain save/load/delete**

```swift
@Test(.dependencies) func keychainRoundTrip() async throws {
  let key = "test.ssh.profile"
  try await keychainClient.savePassword("secret", key)
  let loaded = try await keychainClient.loadPassword(key)
  #expect(loaded == "secret")
  try await keychainClient.deletePassword(key)
}
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SSHCommandSupportTests \
  -only-testing:supacodeTests/KeychainClientTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: compile failure (missing client/utils).

- [ ] **Step 4: Implement keychain + SSH support**

```swift
// KeychainClient.swift
struct KeychainClient: Sendable {
  var savePassword: @Sendable (_ password: String, _ key: String) async throws -> Void
  var loadPassword: @Sendable (_ key: String) async throws -> String?
  var deletePassword: @Sendable (_ key: String) async throws -> Void
}
```

```swift
// SSHCommandSupport.swift
enum SSHCommandSupport {
  static let connectTimeoutSeconds = 8
  static let serverAliveIntervalSeconds = 5
  static let serverAliveCountMax = 3
  static func connectivityOptions() -> [String] { ... }
  static func controlSocketPath(endpointKey: String, temporaryDirectory: String = NSTemporaryDirectory()) -> String { ... }
  static func shellEscape(_ value: String) -> String { ... }
}
```

```swift
// RepositorySettings.swift (repo-level remote session binding)
var defaultRemoteTmuxSessionName: String?
var lastAttachedRemoteTmuxSessionName: String?
```

- [ ] **Step 5: Run tests and commit**

Run same test command from Step 3.  
Expected: PASS.

```bash
git add \
  supacode/Clients/Security/KeychainClient.swift \
  supacode/Infrastructure/SSH/SSHCommandSupport.swift \
  supacode/Features/Settings/Models/RepositorySettings.swift \
  supacodeTests/KeychainClientTests.swift \
  supacodeTests/SSHCommandSupportTests.swift
git commit -m "feat: add keychain client and ssh command primitives"
```

## Task 4: Add Remote Execution + Remote tmux Clients

**Files:**
- Create: `supacode/Clients/Remote/RemoteExecutionClient.swift`
- Create: `supacode/Clients/Remote/RemoteTmuxClient.swift`
- Modify: `supacode/Clients/Shell/ShellClient.swift`
- Test: `supacodeTests/RemoteExecutionClientTests.swift`
- Test: `supacodeTests/RemoteTmuxClientTests.swift`

- [ ] **Step 1: Write failing remote execution tests**

```swift
@Test func remoteExecutionBuildsExpectedSSHArguments() async throws {
  let output = try await remoteExecutionClient.run(
    profile: .fixture(host: "host", user: "dev", port: 2222),
    command: "tmux list-sessions"
  )
  #expect(output.exitCode == 0)
}
```

```swift
@Test func remoteTmuxParsesSessionNames() async throws {
  let sessions = try await remoteTmuxClient.listSessions(profile: .fixture(), timeoutSeconds: 8)
  #expect(sessions == ["main", "ops"])
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteExecutionClientTests \
  -only-testing:supacodeTests/RemoteTmuxClientTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: missing type failures.

- [ ] **Step 3: Implement remote execution contract**

```swift
struct RemoteExecutionClient: Sendable {
  struct Output: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }
  var run: @Sendable (_ profile: SSHHostProfile, _ command: String, _ timeoutSeconds: Int) async throws -> Output
}
```

```swift
struct RemoteTmuxClient: Sendable {
  var listSessions: @Sendable (_ profile: SSHHostProfile, _ timeoutSeconds: Int) async throws -> [String]
  var buildAttachCommand: @Sendable (_ sessionName: String, _ remotePath: String) -> String
  var buildCreateAndAttachCommand: @Sendable (_ preferredName: String, _ remotePath: String) -> String
}
```

- [ ] **Step 4: Add timeout-support path to `ShellClient`**

```swift
// Add helper for timeout process execution used by RemoteExecutionClient.
func runWithTimeout(
  _ executableURL: URL,
  _ arguments: [String],
  _ currentDirectoryURL: URL?,
  timeoutSeconds: Int
) async throws -> ShellOutput { ... }
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Clients/Remote/RemoteExecutionClient.swift \
  supacode/Clients/Remote/RemoteTmuxClient.swift \
  supacode/Clients/Shell/ShellClient.swift \
  supacodeTests/RemoteExecutionClientTests.swift \
  supacodeTests/RemoteTmuxClientTests.swift
git commit -m "feat: add remote ssh execution and tmux clients"
```

## Task 5: Make Git Client Endpoint-Aware for Remote Worktree Ops

**Files:**
- Modify: `supacode/Clients/Repositories/GitClientDependency.swift`
- Modify: `supacode/Clients/Git/GitClient.swift`
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- Modify: `supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift`
- Test: `supacodeTests/GitClientRemoteCommandTests.swift`
- Test: `supacodeTests/RepositoriesFeatureTests.swift`

- [ ] **Step 1: Add failing tests for remote git command composition**

```swift
@Test func remoteWorktreeListUsesSSHGitCRemotePath() async throws {
  let client = GitClient(shell: .failing, remoteExecution: .capturingSuccess)
  _ = try await client.worktrees(for: URL(fileURLWithPath: "/synthetic"), endpoint: .remote(hostProfileID: "h1", remotePath: "/srv/repo"))
  #expect(capturedRemoteCommands.value.contains("git -C '/srv/repo' worktree list"))
}
```

- [ ] **Step 2: Run targeted test and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/GitClientRemoteCommandTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: API mismatch compile failure.

- [ ] **Step 3: Add endpoint-aware API surface**

```swift
// GitClientDependency.swift
var worktreesForEndpoint: @Sendable (URL, RepositoryEndpoint, SSHHostProfile?) async throws -> [Worktree]
var createWorktreeStreamForEndpoint: @Sendable (...) -> AsyncThrowingStream<GitWorktreeCreateEvent, Error>
var removeWorktreeForEndpoint: @Sendable (Worktree, Bool, RepositoryEndpoint, SSHHostProfile?) async throws -> URL
```

```swift
// GitClient.swift
nonisolated func worktrees(
  for repoRoot: URL,
  endpoint: RepositoryEndpoint,
  hostProfile: SSHHostProfile?
) async throws -> [Worktree] { ... }
```

- [ ] **Step 4: Migrate repository reducers to endpoint-aware git calls**

```swift
let endpoint = repository.endpoint
let hostProfile = resolveHostProfile(for: endpoint)
let worktrees = try await gitClient.worktreesForEndpoint(repository.rootURL, endpoint, hostProfile)
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/GitClientRemoteCommandTests \
  -only-testing:supacodeTests/RepositoriesFeatureTests \
  -only-testing:supacodeTests/RepositorySettingsFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: PASS.

```bash
git add \
  supacode/Clients/Repositories/GitClientDependency.swift \
  supacode/Clients/Git/GitClient.swift \
  supacode/Features/Repositories/Reducer/RepositoriesFeature.swift \
  supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift \
  supacodeTests/GitClientRemoteCommandTests.swift \
  supacodeTests/RepositoriesFeatureTests.swift
git commit -m "feat: route git worktree operations through endpoint-aware execution"
```

## Task 6: Implement Host-First Remote Add Flow in Repositories

**Files:**
- Create: `supacode/Features/Repositories/Reducer/RemoteConnectFeature.swift`
- Create: `supacode/Features/Repositories/Views/RemoteConnectSheet.swift`
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- Modify: `supacode/App/ContentView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarFooterView.swift`
- Test: `supacodeTests/RemoteConnectFeatureTests.swift`
- Test: `supacodeTests/RepositoriesFeatureTests.swift`

- [ ] **Step 1: Add failing reducer tests for host-first flow**

```swift
@Test func remoteConnectRequiresHostBeforePathValidation() async {
  let store = TestStore(initialState: RemoteConnectFeature.State()) { RemoteConnectFeature() }
  await store.send(.continueTapped) {
    $0.validationMessage = "Host is required."
  }
}

@Test func submittingValidRemoteFlowCreatesRemoteEntry() async { ... }
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteConnectFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: missing feature/view compile failures.

- [ ] **Step 3: Implement `RemoteConnectFeature` state machine**

```swift
@Reducer
struct RemoteConnectFeature {
  @ObservableState
  struct State: Equatable {
    var hostName = ""
    var hostAddress = ""
    var hostUser = ""
    var hostPortText = ""
    var authMethod: SSHHostProfile.AuthMethod = .publicKey
    var password = ""
    var remotePath = ""
    var isSubmitting = false
    var validationMessage: String?
  }
  enum Action { case continueTapped, submitTapped, delegate(Delegate), ... }
}
```

- [ ] **Step 4: Wire RepositoriesFeature sheet presentation and result handling**

```swift
@Presents var remoteConnect: RemoteConnectFeature.State?
case presentRemoteConnect
case remoteConnect(PresentationAction<RemoteConnectFeature.Action>)
```

```swift
case .remoteConnect(.presented(.delegate(.submitted(let payload)))):
  // create/update host profile, create remote persisted entry, reload repositories
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteConnectFeatureTests \
  -only-testing:supacodeTests/RepositoriesFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: PASS.

```bash
git add \
  supacode/Features/Repositories/Reducer/RemoteConnectFeature.swift \
  supacode/Features/Repositories/Views/RemoteConnectSheet.swift \
  supacode/Features/Repositories/Reducer/RepositoriesFeature.swift \
  supacode/App/ContentView.swift \
  supacode/Features/Repositories/Views/SidebarFooterView.swift \
  supacodeTests/RemoteConnectFeatureTests.swift \
  supacodeTests/RepositoriesFeatureTests.swift
git commit -m "feat: add host-first remote repository onboarding flow"
```

## Task 7: Add SSH Hosts Management in Settings

**Files:**
- Create: `supacode/Features/Settings/Reducer/SSHHostsFeature.swift`
- Create: `supacode/Features/Settings/Views/SSHHostsSettingsView.swift`
- Modify: `supacode/Features/Settings/Views/SettingsSection.swift`
- Modify: `supacode/Features/Settings/Views/SettingsView.swift`
- Modify: `supacode/Features/Settings/Reducer/SettingsFeature.swift`
- Test: `supacodeTests/SettingsFeatureSSHHostsTests.swift`

- [ ] **Step 1: Write failing settings tests for CRUD and in-use delete guard**

```swift
@Test func addHostAppendsProfile() async { ... }
@Test func deleteHostFailsWhenBoundRepositoriesExist() async { ... }
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SettingsFeatureSSHHostsTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: missing section/feature failures.

- [ ] **Step 3: Implement feature and add settings section**

```swift
// SettingsSection.swift
case sshHosts
```

```swift
// SettingsView.swift
Label("SSH Hosts", systemImage: "network")
  .tag(SettingsSection.sshHosts)
```

```swift
// SettingsFeature.State
var sshHosts: SSHHostsFeature.State?
```

- [ ] **Step 4: Build UI with tooltips and validation**

```swift
Button("Add Host") { store.send(.addHostTapped) }
  .help("Add SSH host profile")
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Features/Settings/Reducer/SSHHostsFeature.swift \
  supacode/Features/Settings/Views/SSHHostsSettingsView.swift \
  supacode/Features/Settings/Views/SettingsSection.swift \
  supacode/Features/Settings/Views/SettingsView.swift \
  supacode/Features/Settings/Reducer/SettingsFeature.swift \
  supacodeTests/SettingsFeatureSSHHostsTests.swift
git commit -m "feat: add ssh host profile management in settings"
```

## Task 8: Implement Always-Show Remote tmux Session Picker

**Files:**
- Create: `supacode/Features/Repositories/Reducer/RemoteSessionPickerFeature.swift`
- Create: `supacode/Features/Repositories/Views/RemoteSessionPickerSheet.swift`
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`
- Modify: `supacode/App/ContentView.swift`
- Test: `supacodeTests/RemoteSessionPickerFeatureTests.swift`
- Test: `supacodeTests/RepositoriesFeatureTests.swift`

- [ ] **Step 1: Add failing tests for "always picker" behavior**

```swift
@Test func selectingRemoteWorktreeWithSessionsAlwaysPresentsPicker() async { ... }
@Test func pickerAttachSelectionPersistsLastAttachedSessionName() async { ... }
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteSessionPickerFeatureTests \
  -only-testing:supacodeTests/RepositoriesFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: missing picker flow failures.

- [ ] **Step 3: Implement picker reducer and connect to remote worktree select path**

```swift
@Presents var remoteSessionPicker: RemoteSessionPickerFeature.State?
case remoteSessionsLoaded(worktreeID: Worktree.ID, sessions: [String])
```

```swift
if repository.endpoint.isRemote {
  let sessions = try await remoteTmuxClient.listSessions(profile, 8)
  await send(.remoteSessionsLoaded(worktreeID: worktreeID, sessions: sessions))
}
```

- [ ] **Step 4: Persist session choice into repo settings**

```swift
@Shared(.repositorySettings(repository.rootURL)) var repositorySettings
$repositorySettings.withLock {
  $0.lastAttachedRemoteTmuxSessionName = selectedSession
}
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Features/Repositories/Reducer/RemoteSessionPickerFeature.swift \
  supacode/Features/Repositories/Views/RemoteSessionPickerSheet.swift \
  supacode/Features/Repositories/Reducer/RepositoriesFeature.swift \
  supacode/App/ContentView.swift \
  supacodeTests/RemoteSessionPickerFeatureTests.swift \
  supacodeTests/RepositoriesFeatureTests.swift
git commit -m "feat: add always-on remote tmux session picker flow"
```

## Task 9: Wire Remote Terminal Attach + Reconnect

**Files:**
- Modify: `supacode/Clients/Terminal/TerminalClient.swift`
- Modify: `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
- Modify: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- Modify: `supacode/Features/App/Reducer/AppFeature.swift`
- Test: `supacodeTests/WorktreeTerminalManagerTests.swift`
- Test: `supacodeTests/AppFeatureRunScriptTests.swift`

- [ ] **Step 1: Add failing tests for reconnect event handling**

```swift
@Test func remoteSurfaceExitEmitsReconnectRequestedEvent() async { ... }
@Test func appFeatureHandlesReconnectByRequestingSessionPicker() async { ... }
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/WorktreeTerminalManagerTests \
  -only-testing:supacodeTests/AppFeatureRunScriptTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: missing terminal event/API failures.

- [ ] **Step 3: Add terminal command/event hooks**

```swift
// TerminalClient.Command
case setRemoteAttachCommand(Worktree, command: String?)

// TerminalClient.Event
case remoteReconnectRequested(worktreeID: Worktree.ID)
```

```swift
// WorktreeTerminalState.handleCloseRequest(...)
if isRemoteWorktree && tabWasPrimaryRemoteAttach {
  onRemoteReconnectRequested?()
}
```

- [ ] **Step 4: Handle reconnect in AppFeature**

```swift
case .terminalEvent(.remoteReconnectRequested(let worktreeID)):
  return .send(.repositories(.requestRemoteSessionPickerForReconnect(worktreeID)))
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Clients/Terminal/TerminalClient.swift \
  supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift \
  supacode/Features/Terminal/Models/WorktreeTerminalState.swift \
  supacode/Features/App/Reducer/AppFeature.swift \
  supacodeTests/WorktreeTerminalManagerTests.swift \
  supacodeTests/AppFeatureRunScriptTests.swift
git commit -m "feat: add remote terminal attach and reconnect signaling"
```

## Task 10: Command Palette + Menu Integration for Remote Connect

**Files:**
- Modify: `supacode/Features/CommandPalette/CommandPaletteItem.swift`
- Modify: `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift`
- Modify: `supacode/Features/App/Reducer/AppFeature.swift`
- Modify: `supacode/Commands/WorktreeCommands.swift`
- Test: `supacodeTests/CommandPaletteFeatureTests.swift`
- Test: `supacodeTests/AppFeatureCommandPaletteTests.swift`

- [ ] **Step 1: Add failing command palette tests**

```swift
@Test func includesRemoteConnectGlobalAction() {
  let items = CommandPaletteFeature.commandPaletteItems(from: .init())
  #expect(items.contains(where: { $0.kind == .remoteConnect }))
}
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/CommandPaletteFeatureTests \
  -only-testing:supacodeTests/AppFeatureCommandPaletteTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: enum case missing.

- [ ] **Step 3: Add command palette kind/delegate/action mapping**

```swift
enum CommandPaletteItem.Kind: Equatable {
  case remoteConnect
}

enum CommandPaletteFeature.Delegate: Equatable {
  case remoteConnect
}
```

- [ ] **Step 4: Route delegate in AppFeature and add menu item**

```swift
case .commandPalette(.delegate(.remoteConnect)):
  return .send(.repositories(.presentRemoteConnect))
```

```swift
Button("Connect Remote Repository...", systemImage: "network") {
  store.send(.repositories(.presentRemoteConnect))
}
.help("Connect Remote Repository")
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Features/CommandPalette/CommandPaletteItem.swift \
  supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift \
  supacode/Features/App/Reducer/AppFeature.swift \
  supacode/Commands/WorktreeCommands.swift \
  supacodeTests/CommandPaletteFeatureTests.swift \
  supacodeTests/AppFeatureCommandPaletteTests.swift
git commit -m "feat: expose remote connect in command palette and menu"
```

## Task 11: Guard Local-Only Actions for Remote Repositories

**Files:**
- Modify: `supacode/Features/App/Reducer/AppFeature.swift`
- Modify: `supacode/Features/Settings/Views/RepositorySettingsView.swift`
- Modify: `supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift`
- Test: `supacodeTests/RepositorySettingsFeatureTests.swift`
- Test: `supacodeTests/AppFeatureDefaultEditorTests.swift`

- [ ] **Step 1: Add failing tests for local-only action disabling**

```swift
@Test func remoteRepositoryDisablesOpenFinderEditorActions() async { ... }
@Test func repositorySettingsHidesLocalPathDependentOptionsForRemoteRepo() { ... }
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RepositorySettingsFeatureTests \
  -only-testing:supacodeTests/AppFeatureDefaultEditorTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: assertions fail because remote/local distinctions absent.

- [ ] **Step 3: Implement local-only guards**

```swift
guard selectedRepository?.endpoint == .local else {
  state.alert = messageAlert(title: "Unavailable for remote repository", message: "Use terminal attach for remote repositories.")
  return .none
}
```

- [ ] **Step 4: Add remote-specific repository settings fields**

```swift
Section("Remote") {
  Text("Host profile: \(resolvedHostDisplayName)")
  TextField("Default tmux session", text: settings.defaultRemoteTmuxSessionNameString)
}
```

- [ ] **Step 5: Run tests and commit**

Run command from Step 2.  
Expected: PASS.

```bash
git add \
  supacode/Features/App/Reducer/AppFeature.swift \
  supacode/Features/Settings/Views/RepositorySettingsView.swift \
  supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift \
  supacodeTests/RepositorySettingsFeatureTests.swift \
  supacodeTests/AppFeatureDefaultEditorTests.swift
git commit -m "feat: add remote-aware action guards and repository settings"
```

## Task 12: Final Verification, Build, and Documentation

**Files:**
- Modify: `README.md`
- Modify: `doc-onevcat/change-list.md`

- [ ] **Step 1: Run format/lint/check**

Run: `make check`  
Expected: no formatting or lint errors.

- [ ] **Step 2: Run targeted remote test suite**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteConnectFeatureTests \
  -only-testing:supacodeTests/RemoteSessionPickerFeatureTests \
  -only-testing:supacodeTests/RemoteExecutionClientTests \
  -only-testing:supacodeTests/RemoteTmuxClientTests \
  -only-testing:supacodeTests/GitClientRemoteCommandTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run: `make test`  
Expected: PASS.

- [ ] **Step 4: Build app**

Run: `make build-app`  
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit docs + final integration**

```bash
git add README.md doc-onevcat/change-list.md
git commit -m "docs: document remote ssh and tmux support"
```

---

## Spec Coverage Check (Self-Review)

- Shared/persisted SSH host profiles: Task 2 + Task 7
- Host-first remote add flow: Task 6
- Reuse host profile across repos: Task 2 + Task 6 + Task 7
- Native ssh/tmux command usage: Task 3 + Task 4 + Task 8
- Always show tmux session picker: Task 8
- SSH-only reconnect continuity (no mosh transport): Task 9
- Remote git worktree operations over SSH: Task 5
- Repo-level tmux session bindings: Task 3 + Task 8 + Task 11
- Error handling and operation-level failures: Task 4 + Task 6 + Task 8 + Task 11
- Testing matrix and rollout-quality verification: Tasks 1-12 with final checks in Task 12

No uncovered spec requirement remains.

## Placeholder Scan (Self-Review)

- No `TBD`, `TODO`, or deferred implementation markers.
- Every coding task includes explicit files, commands, and concrete code snippets.
- Every task includes a commit step with explicit `git add` paths.

## Type Consistency Check (Self-Review)

- `RepositoryEndpoint`, `SSHHostProfile`, `RemoteExecutionClient`, and `RemoteTmuxClient` are introduced once and referenced consistently in later tasks.
- Remote picker action names and state references are consistent across Repositories/App/ContentView tasks.
- Repository settings remote session fields use consistent names (`defaultRemoteTmuxSessionName`, `lastAttachedRemoteTmuxSessionName`).
