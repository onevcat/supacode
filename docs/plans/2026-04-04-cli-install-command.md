# CLI Install Command Implementation Plan

**Goal:** Allow users to install the `prowl` CLI tool from within the Prowl app via three entry points: Settings, Prowl menu, and Command Palette.

**Scope:**
- In: CLIInstallClient dependency, Advanced Settings UI, Prowl menu item, Command Palette item, AppFeature wiring, Makefile CLI embedding, tests
- Out: Auto-prompting on first launch, uninstall UI (can be added later), CLI build as part of Xcode build phase (manual `make build-cli` for now)

**Architecture:**
- `CLIInstallClient`: TCA dependency client that handles symlink creation, status checking, and bundled binary path resolution
- Install action lives in `AppFeature` — all three entry points (Settings, Menu, Command Palette) funnel into the same `installCLI` action
- CLI binary is embedded at `Prowl.app/Contents/Resources/prowl-cli/prowl`
- Installation creates a symlink: `/usr/local/bin/prowl` → bundled binary path
- Advanced Settings gets a new "Command Line Tool" section showing install status + install/uninstall button

**Acceptance / Verification:**
- `make build-app` succeeds
- All existing tests pass
- New CLIInstallClient tests pass
- New AppFeature CLI install reducer tests pass
- Menu item "Install Command Line Tool" visible under Prowl menu
- Command Palette shows "Install Command Line Tool" item
- Settings > Advanced shows CLI install section with status and action button

---

## Task 1: Create CLIInstallClient dependency

**Files:**
- Create: `supacode/Clients/CLIInstall/CLIInstallClient.swift`

**Steps:**
1. Create `CLIInstallClient` struct following `WorkspaceClient` pattern
2. Provide operations:
   - `bundledCLIURL: @Sendable () -> URL?` — returns `Bundle.main.resourceURL/prowl-cli/prowl`
   - `installationStatus: @Sendable () -> CLIInstallStatus` — checks if symlink exists and points to correct target
   - `install: @Sendable (URL) async throws -> Void` — creates symlink at given path (default `/usr/local/bin/prowl`)
   - `uninstall: @Sendable (URL) async throws -> Void` — removes symlink at given path
3. Define `CLIInstallStatus` enum: `.notInstalled`, `.installed(path: String)`, `.installedDifferentSource(path: String)`
4. Implement `DependencyKey` with `liveValue` and `testValue`
5. Register in `DependencyValues`

**Notes:**
- Use `FileManager` for symlink operations
- `install` should create `/usr/local/bin` directory if it doesn't exist
- Check if destination already exists before creating symlink; if it's a symlink pointing elsewhere, report `.installedDifferentSource`

---

## Task 2: Add CLI install actions to AppFeature

**Files:**
- Modify: `supacode/Features/App/Reducer/AppFeature.swift` (add actions and reducer cases)

**Steps:**
1. Add new actions to AppFeature.Action:
   - `installCLI`
   - `uninstallCLI`
   - `cliInstallResult(Result<String, CLIInstallError>)` — result of install/uninstall with success message or error
2. Add `@Dependency(CLIInstallClient.self)` to AppFeature
3. Implement reducer cases:
   - `installCLI`: run `.install()` via client, send result action
   - `uninstallCLI`: run `.uninstall()` via client, send result action
   - `cliInstallResult`: show alert with success/failure message
4. Add `CLIInstallError` type for error reporting

---

## Task 3: Add CLI install section to Advanced Settings

**Files:**
- Modify: `supacode/Features/Settings/Views/AdvancedSettingsView.swift` (add CLI section)

**Steps:**
1. Add a new `Section("Command Line Tool")` in `AdvancedSettingsView`
2. Show current installation status (use `CLIInstallClient` to check)
3. Show Install/Uninstall button based on status
4. Button sends action to the `AppFeature` store (the settings view already receives `StoreOf<SettingsFeature>`, but we need to access `AppFeature` actions — use a callback or add delegate actions)

**Design decision:** Since AdvancedSettingsView only has `StoreOf<SettingsFeature>`, add delegate actions to SettingsFeature:
- `SettingsFeature.Delegate.installCLIRequested`
- `SettingsFeature.Delegate.uninstallCLIRequested`
- Handle these in AppFeature's `.settings(.delegate(...))` case

**Notes:**
- Show the install path (`/usr/local/bin/prowl`) in the UI
- Show a green checkmark or status text for installed state
- The view should refresh status when the settings tab appears

---

## Task 4: Add menu item in Prowl menu

**Files:**
- Modify: `supacode/App/supacodeApp.swift` (add menu item in Prowl menu group)

**Steps:**
1. Add a `CommandGroup(after: .appSettings)` or within the existing Prowl menu area
2. Add "Install Command Line Tool..." button
3. Button sends `store.send(.installCLI)` action
4. Add appropriate `.help()` text

---

## Task 5: Add Command Palette item

**Files:**
- Modify: `supacode/Features/CommandPalette/CommandPaletteItem.swift` (add Kind case)
- Modify: `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift` (add item, delegate, mapping)
- Modify: `supacode/Features/App/Reducer/AppFeature.swift` (handle new delegate)

**Steps:**
1. Add `case installCLI` to `CommandPaletteItem.Kind`
2. Update `isGlobal` and `isRootAction` to return `true` for `.installCLI`
3. Add `case installCLI` to `CommandPaletteFeature.Delegate`
4. Add `CommandPaletteItem` to `commandPaletteItems()` function
5. Add ID `globalInstallCLI` to `CommandPaletteItemID`
6. Add to `globalIDs` array
7. Update `delegateAction(for:)` mapping
8. Update `appShortcutCommandID` (return nil for installCLI)
9. Handle `.commandPalette(.delegate(.installCLI))` in AppFeature reducer

---

## Task 6: Makefile integration for CLI embedding

**Files:**
- Modify: `Makefile` (add target to build CLI for bundle)

**Steps:**
1. Add `build-cli-release` target: `swift build -c release --product prowl`
2. Add `embed-cli` target: copies release binary to `Resources/prowl-cli/prowl`
3. Update `build-app` to depend on `embed-cli` (or document manual step)
4. Add `Resources/prowl-cli/` to Xcode "Copy Bundle Resources" if not auto-included

**Notes:**
- For development, `Resources/prowl-cli/prowl` can be a placeholder — the actual install will use the bundled path at runtime

---

## Task 7: Tests for CLIInstallClient

**Files:**
- Create: `supacodeTests/CLIInstallClientTests.swift`

**Steps:**
1. Test `installationStatus` returns `.notInstalled` when no symlink exists
2. Test `installationStatus` returns `.installed` when valid symlink exists
3. Test `installationStatus` returns `.installedDifferentSource` when symlink points elsewhere
4. Test `install` creates symlink at expected path
5. Test `install` creates parent directory if needed
6. Test `uninstall` removes symlink
7. Test `uninstall` does not remove non-symlink files (safety)

**Notes:**
- Use temp directories for test isolation
- Test with actual FileManager operations (not mocks) for the live client

---

## Task 8: Tests for AppFeature CLI install reducer

**Files:**
- Create: `supacodeTests/AppFeatureCLIInstallTests.swift`

**Steps:**
1. Test `.installCLI` action triggers client install call
2. Test `.uninstallCLI` action triggers client uninstall call
3. Test success result shows appropriate alert
4. Test failure result shows error alert
5. Test Command Palette delegate `.installCLI` forwards to `.installCLI` action
6. Test Settings delegate `.installCLIRequested` forwards to `.installCLI` action

---

## Task 9: Build verification

**Steps:**
1. Run `make build-app` — verify success
2. Run existing tests — verify no regressions
3. Run new tests — verify all pass
4. Run `make lint` — verify no lint errors
