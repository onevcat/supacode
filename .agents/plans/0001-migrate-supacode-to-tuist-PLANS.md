# Migrate Supacode to Tuist and retire the checked-in Xcode project

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

There is no repository-local `PLANS.md` in this repo today. Treat this file as the complete source of truth for the migration.

## Purpose / Big Picture

After this change, Supacode will build, test, archive, and release from a generated Tuist workspace instead of from the checked-in `supacode.xcodeproj`. A developer will be able to clone the repo, run `make generate-project`, `make build-app`, and `make test`, and get the same app behavior without hand-editing a project file. The release workflows will stop mutating `supacode.xcodeproj/project.pbxproj` and `supacode/App/supacodeApp.swift` during CI. The specific release-tip break we just hit will disappear because the bundled CLI will no longer archive as `/usr/local/bin/supacode`; it will be copied into the app bundle as `Contents/Resources/bin/supacode`, which is already the runtime contract expected by `supacode/Features/Settings/BusinessLogic/CLIInstaller.swift`.

The complexity we are paying today is split across too many places. The checked-in project file owns target wiring, version numbers, and some build settings. `Makefile` owns Ghostty build orchestration. `.github/actions/setup-macos/action.yml` owns more Ghostty and package cache knowledge. `.github/workflows/release.yml` and `.github/workflows/release-tip.yml` mutate the project file for build numbering and patch telemetry secrets directly into `supacode/App/supacodeApp.swift`. The result is change amplification and unknown unknowns: one target setting change can silently change archive semantics, which is exactly what happened when `supacode-cli` shipped with `SKIP_INSTALL = NO`. The migration should create one build source of truth, hide Ghostty and CLI packaging policy behind Tuist targets and scripts, and leave callers with a simpler interface: use `make`, not project surgery.

## Progress

- [x] (2026-04-14 08:17Z) Inspected `supaterm` and extracted the concrete Tuist patterns worth copying: root manifests, `Tuist/Package.swift`, stamped `make` generation targets, a `foreignBuild` Ghostty target, an app post-build script that copies the CLI into `Contents/Resources/bin`, and release workflows that read build numbers from an xcconfig instead of mutating a project file.
- [x] (2026-04-14 08:17Z) Inspected `supacode` build, release, and runtime boundaries: `Makefile`, `.github/actions/setup-macos/action.yml`, `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.github/workflows/release-tip.yml`, `supacode.xcodeproj/project.pbxproj`, `supacode/Info.plist`, `supacode/App/supacodeApp.swift`, `supacode/Features/Settings/BusinessLogic/CLIInstaller.swift`, and `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`.
- [x] (2026-04-14 08:17Z) Reproduced the release-tip archive problem locally and confirmed that the current `supacode-cli` target archives with `SKIP_INSTALL = NO` and `INSTALL_PATH = /usr/local/bin`.
- [x] (2026-04-14 08:17Z) Chose the migration shape: keep the current repo root layout, introduce a minimal Tuist graph first, then remove the checked-in Xcode project once parity is proven.
- [ ] Add Tuist manifests and configuration files: `Tuist.swift`, `Workspace.swift`, `Project.swift`, `Tuist/Package.swift`, `Tuist/Package.resolved`, `Configurations/Project.xcconfig`, and `scripts/build-ghostty.sh`.
- [ ] Update the runtime and packaging boundaries so analytics configuration and CLI embedding no longer depend on CI source patching or on archive install paths.
- [ ] Switch `Makefile`, GitHub Actions, and version bumping to the generated workspace and xcconfig-based versioning.
- [ ] Delete `supacode.xcodeproj`, ignore generated project artifacts, and verify the repo still builds, tests, and archives cleanly from Tuist.

## Surprises & Discoveries

- Observation: The current release-tip failure is not a flaky runner issue. The first bad commit added a command-line tool target that archives as an installable product.
  Evidence: `xcodebuild -project supacode.xcodeproj -target supacode-cli -configuration Release -showBuildSettings` reports `SKIP_INSTALL = NO` and `INSTALL_PATH = /usr/local/bin`, and a local archive contains `build/supacode.xcarchive/Products/usr/local/bin/supacode`.

- Observation: Once the archive contains both `Products/Applications/supacode.app` and `Products/usr/local/bin/supacode`, `xcodebuild -exportArchive` no longer accepts `method = developer-id`.
  Evidence: local reproduction returned `error: exportArchive exportOptionsPlist error for key "method" expected one {} but found developer-id`.

- Observation: The app already expects the bundled CLI to live inside the app bundle, not at an archive install path.
  Evidence: `supacode/Features/Settings/BusinessLogic/CLIInstaller.swift` resolves `Bundle.main.resourceURL?.appending(path: "bin/supacode")`, and `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` prepends that same `Resources/bin` directory to `PATH`.

- Observation: Release workflows currently mutate source code to inject secrets.
  Evidence: both `.github/workflows/release.yml` and `.github/workflows/release-tip.yml` run `sed -i ''` against `supacode/App/supacodeApp.swift` to replace `__SENTRY_DSN__`, `__POSTHOG_API_KEY__`, and `__POSTHOG_HOST__`.

- Observation: Version metadata is still stored in the checked-in project file instead of in a data-only configuration file.
  Evidence: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `supacode.xcodeproj/project.pbxproj`, and `make bump-version` edits that file directly.

## Decision Log

- Decision: Keep the repo root layout and generate `supacode.xcodeproj` and `supacode.xcworkspace` at the repo root rather than moving the app under `apps/mac`.
  Rationale: The architectural goal is to replace the build source of truth, not to re-home the codebase. A directory move would add noise and conflict risk without hiding any additional complexity.
  Date/Author: 2026-04-14 / Codex

- Decision: Start with a minimal Tuist graph containing `supacode`, `supacodeTests`, `supacode-cli`, and `GhosttyKit`, instead of copying `supaterm`’s full module decomposition.
  Rationale: `supacode` already has strong folder boundaries, but its current pain is build orchestration, archive semantics, and CI mutation. Splitting the app into many new frameworks now would change too much surface area at once and obscure the core migration.
  Date/Author: 2026-04-14 / Codex

- Decision: Move build numbers and runtime secrets into configuration, not into Swift source and not into the generated project.
  Rationale: `Configurations/Project.xcconfig` and a temporary CI-only override xcconfig create a deeper boundary. Workflows can provide values without knowing where inside the app source those values are consumed.
  Date/Author: 2026-04-14 / Codex

- Decision: Make Tuist remote cache optional, not a blocker for the migration.
  Rationale: `supaterm` uses `TUIST_TOKEN` and a warm-cache workflow, but that is an optimization. The complexity dividend comes from making Tuist the source of truth and from fixing packaging. We can add remote cache later if the basic move succeeds.
  Date/Author: 2026-04-14 / Codex

- Decision: Allow a short additive phase where both the old project and the Tuist manifests exist, but require the checked-in `supacode.xcodeproj` to be deleted before this plan is considered complete.
  Rationale: A temporary parallel path reduces migration risk, while the final state still has one source of truth and no dead code.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

This document is the initial migration plan. No implementation has happened yet. The intended outcome is one build graph owned by Tuist, an app-only archive, no release-time source patching, and a cleaner CI surface. The main risk is not technical feasibility; it is accidentally preserving two build systems at once. The plan therefore treats deletion of the checked-in Xcode project as a required end state, not an optional cleanup.

## Context and Orientation

Supacode is currently built from `Makefile` by calling `xcodebuild -project supacode.xcodeproj`. The app source lives in `supacode/`, the tests live in `supacodeTests/`, the new CLI tool lives in `supacode-cli/`, Ghostty source is in the `ThirdParty/ghostty` submodule, and the bundled `git-wt` helper lives in `Resources/git-wt`. The current project file is `supacode.xcodeproj/project.pbxproj`, and the current package resolution file is `supacode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

A “generated workspace” means the `.xcodeproj` and `.xcworkspace` files are outputs, not handwritten source files. In the desired state, the source files are `Project.swift`, `Workspace.swift`, `Tuist.swift`, `Tuist/Package.swift`, `Tuist/Package.resolved`, and `Configurations/Project.xcconfig`. A “foreign build target” is a Tuist target whose output is produced by an external build script instead of by Swift compilation. That is the right boundary for Ghostty because callers should depend on “GhosttyKit exists here” rather than on the exact Zig commands and rsync steps that produce it.

Today, the people paying the complexity tax are developers making project changes and CI workflows assembling release artifacts. A developer changing dependencies or targets must touch the checked-in `.pbxproj`. CI knows where version numbers live inside that project file and where telemetry placeholders live inside `supacode/App/supacodeApp.swift`. The app archive also leaks packaging policy because the CLI target’s install path changes what kind of archive Xcode thinks it has produced. After this change, that knowledge should move behind three boundaries: Tuist manifests own the graph, `Configurations/Project.xcconfig` owns version and default app metadata values, and post-build scripts own Ghostty and CLI embedding.

The current CLI contract must not change. `CLIInstaller` installs a symlink from `/usr/local/bin/supacode` to `Bundle.main/Contents/Resources/bin/supacode`, and terminal sessions prepend that `Resources/bin` directory to `PATH`. The migration must preserve that location exactly while changing only how the binary arrives there during build time.

The current release workflows also reveal a second hidden problem: Supacode reads Sentry and PostHog values from hard-coded string literals inside `supacode/App/supacodeApp.swift`. That forces CI to rewrite application source before archiving. Tuist gives us a better place to carry these values: build settings flowing into `supacode/Info.plist`, with the app reading `Bundle.main.infoDictionary`.

## Plan of Work

### Milestone 1: introduce Tuist as the new graph source

Create `Tuist.swift`, `Workspace.swift`, `Project.swift`, `Tuist/Package.swift`, `Tuist/Package.resolved`, and `Configurations/Project.xcconfig` at the repo root. `Tuist.swift` should pin the compatible Xcode range to macOS 26-era Xcode and the Swift version to the value already used by the current project. `Workspace.swift` should define a `supacode` scheme that builds the app target, runs the unit-test target, and archives the release configuration. `Tuist/Package.swift` should become the new package source of truth by copying the versions currently pinned in `supacode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and by mapping product types explicitly: Point-Free libraries such as `ComposableArchitecture`, `Dependencies`, `DependenciesTestSupport`, `Sharing`, `CustomDump`, `Clocks`, `ConcurrencyExtras`, and `IdentifiedCollections` should build as static frameworks, while `Sparkle`, `Sentry`, `PostHog`, and `Kingfisher` should remain frameworks.

`Project.swift` should define four targets. The first is `GhosttyKit`, a `foreignBuild` target whose output path is `.build/ghostty/GhosttyKit.xcframework`. The second is `supacode-cli`, a `.commandLineTool` target that builds from `supacode-cli/` and preserves the current executable name `supacode`. The third is `supacode`, an `.app` target that builds from the existing app directories and depends on `GhosttyKit`, `supacode-cli`, and the Swift package products imported by the app. The fourth is `supacodeTests`, a `.unitTests` target that builds from `supacodeTests/` and carries forward the current host-app settings: `TEST_HOST = $(BUILT_PRODUCTS_DIR)/supacode.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/supacode` and `BUNDLE_LOADER = $(TEST_HOST)`. Keep the target graph minimal at first; do not introduce extra framework targets unless the compiler or linker forces that decision.

The purpose of this milestone is not to fix every workflow yet. It is to prove that a generated workspace can build and test the same code with one owned graph. During this milestone, it is acceptable to keep the checked-in `supacode.xcodeproj` in the repo while validating parity, but do not edit it further unless a migration emergency makes that unavoidable.

### Milestone 2: move packaging and runtime configuration behind owned boundaries

Add `scripts/build-ghostty.sh` and base it on the `supaterm` pattern. The script must accept `--print-fingerprint`; compute a fingerprint from the Ghostty submodule revision, local Ghostty changes, untracked Ghostty files, the build script itself, `mise.toml`, and `.gitmodules`; and populate `.build/ghostty/` with `GhosttyKit.xcframework`, `share/ghostty`, and `share/terminfo`. It should also normalize `module.modulemap` files inside the generated xcframework the same way `supaterm` does so the framework remains importable. This script hides Zig invocation details from both `Makefile` and CI.

Update the `supacode` target in `Project.swift` to copy Ghostty resources from `.build/ghostty/share/ghostty` and `.build/ghostty/share/terminfo` into the built app bundle during a post-build script. Do not keep writing generated assets into tracked top-level paths like `Frameworks/GhosttyKit.xcframework`, `Resources/ghostty`, or `Resources/terminfo`. Those paths are an implementation leak and they dirty the working tree.

Change the `supacode-cli` target settings so `SKIP_INSTALL = YES`. Then add a post-build script on the `supacode` app target that copies the built CLI executable into `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/bin/supacode`. Mirror the search logic from `supaterm`: look first in `$(BUILT_PRODUCTS_DIR)/supacode`, then in `$(UNINSTALLED_PRODUCTS_DIR)/$(PLATFORM_NAME)/supacode`, fail loudly if neither exists, and write the final binary to `Contents/Resources/bin/supacode`. This concentrates the CLI packaging policy in one place and removes the archive-level special case that currently breaks `release-tip`.

Move runtime secrets out of `supacode/App/supacodeApp.swift`. Add `supacode/App/AppCrashReporting.swift` and `supacode/App/AppTelemetry.swift`, modeled on the `supaterm` equivalents, so both modules read `SentryDSN`, `PostHogAPIKey`, and `PostHogHost` from `Bundle.main.infoDictionary`. Update `supacode/App/supacodeApp.swift` to call these helpers instead of holding raw placeholder strings. Update `supacode/Info.plist` so it contains `CFBundleShortVersionString = $(MARKETING_VERSION)`, `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, `LSApplicationCategoryType = public.app-category.developer-tools`, `SentryDSN = $(SENTRY_DSN)`, `PostHogAPIKey = $(POSTHOG_API_KEY)`, and `PostHogHost = $(POSTHOG_HOST)`, while preserving the existing URL scheme, type declaration, Sparkle keys, and permission strings. `Configurations/Project.xcconfig` should define `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `SENTRY_DSN`, `POSTHOG_API_KEY`, and `POSTHOG_HOST`, with empty values for the secrets in local builds so the app simply does not initialize those services when the values are absent.

This milestone is where the complexity dividend appears. Callers no longer need to know how Ghostty is built, how the CLI gets into the bundle, or where secrets live in Swift source. The app target owns those rules.

### Milestone 3: switch developer commands and CI to the generated workspace, then delete the old project

Rewrite `Makefile` so Tuist generation is hidden behind stable developer commands. Add `generate-project` and `generate-project-sources` targets backed by a stamp directory under `.build/.tuist-generated-stamps`, following the pattern used by `supaterm`. `make build-app`, `make run-app`, `make archive`, and `make test` should depend on generation and then use `xcodebuild -workspace supacode.xcworkspace -scheme supacode`. Preserve the existing user-facing commands wherever reasonable so the developer interface becomes simpler, not different for its own sake. Keep `make bump-version`, but make it read and write `Configurations/Project.xcconfig` instead of editing `supacode.xcodeproj/project.pbxproj`.

Update `.github/actions/setup-macos/action.yml` so it installs `mise`, installs Tuist via `mise.toml`, and caches `.build/ghostty` rather than caching generated resources under `Frameworks/` and `Resources/`. Add `tuist = <pinned version>` to `mise.toml`. It is acceptable to keep the existing output formatter tooling rather than switching to `xcbeautify`; output formatting is incidental and should not dominate the migration.

Update `.github/workflows/test.yml`, `.github/workflows/release.yml`, and `.github/workflows/release-tip.yml` to use the generated workspace and xcconfig-based versioning. The release workflows should stop editing `supacode/App/supacodeApp.swift` and stop editing `supacode.xcodeproj/project.pbxproj`. Instead, they should write a temporary `build/ReleaseOverrides.xcconfig` containing `CURRENT_PROJECT_VERSION`, `SENTRY_DSN`, `POSTHOG_API_KEY`, and `POSTHOG_HOST`, then pass that file to `xcodebuild` through `XCODE_XCCONFIG_FILE` or an equivalent supported override. `release-tip` should compute the derived build number from `Configurations/Project.xcconfig`, not from a project file. The archive/export steps should continue to use the existing notarization and DMG flow, but the archive should now contain only `Products/Applications/supacode.app`.

Once build, test, and release parity are demonstrated from Tuist, delete `supacode.xcodeproj`, remove `supacode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, and update `.gitignore` to ignore generated `supacode.xcodeproj/`, `supacode.xcworkspace/`, and `Tuist/Dependencies/`. This subtraction is not optional. Leaving both the Tuist manifests and the checked-in project would preserve the exact split-brain complexity we are trying to remove.

## Concrete Steps

Run all commands from the repository root, `/Users/Developer/code/github.com/supabitapp/supacode`, unless a step says otherwise.

First, introduce the Tuist manifests and make sure package resolution succeeds.

    $ mise install
    $ mise exec -- tuist install
    $ make generate-project

The expected result is a generated `supacode.xcodeproj` and `supacode.xcworkspace`, with `Tuist/Package.resolved` present and no need to open or edit a handwritten project.

Next, validate that the generated workspace builds and tests the same app.

    $ make build-app
    $ make test

The expected result is a successful Debug build and a passing macOS test suite.

Then validate the CLI packaging boundary directly.

    $ xcodebuild -workspace supacode.xcworkspace -target supacode-cli -configuration Release -showBuildSettings | rg "SKIP_INSTALL = YES|INSTALL_PATH ="

The expected result is `SKIP_INSTALL = YES`. `INSTALL_PATH` may still resolve for the target type, but it must no longer matter because the tool is uninstalled and copied into the app bundle by the app target.

After that, produce an unsigned release archive to verify archive shape without requiring local signing credentials.

    $ rm -rf build
    $ xcodebuild -workspace supacode.xcworkspace -scheme supacode -configuration Release -destination "generic/platform=macOS" -archivePath build/supacode.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
    $ find build/supacode.xcarchive/Products -maxdepth 4 -print
    $ plutil -p build/supacode.xcarchive/Info.plist

The expected result is that `find` prints `build/supacode.xcarchive/Products/Applications/supacode.app` and does not print `build/supacode.xcarchive/Products/usr/local/bin/supacode`. The archive `Info.plist` should include `ApplicationProperties`, which is the signature of an app archive that `xcodebuild -exportArchive` can export with `method = developer-id`.

Finally, verify that the source patching path is gone.

    $ rg "__SENTRY_DSN__|__POSTHOG_API_KEY__|__POSTHOG_HOST__" supacode .github/workflows

The expected result is no matches in `supacode/` and no workflow steps that rewrite Swift source. Workflow matches are acceptable only if they are part of a temporary migration commit that has not yet removed the old path; by the final state, the workflows should write a temporary override xcconfig instead.

## Validation and Acceptance

The migration is complete only when all of the following behaviors are true.

A developer can run `make generate-project`, `make build-app`, and `make test` from a clean clone and never touch a checked-in Xcode project file. Opening the app in Xcode means opening the generated workspace.

The app still launches, still finds Ghostty resources, still exposes the `git-wt` helper from the bundle, and still installs the CLI by symlinking `/usr/local/bin/supacode` to `Contents/Resources/bin/supacode`. Terminal sessions still resolve `supacode` from that bundled `Resources/bin` directory.

An unsigned local archive built from the generated workspace contains only the app under `Products/Applications`. There is no archived `usr/local/bin/supacode`, and `xcodebuild -exportArchive` no longer fails for the structural reason that broke `release-tip`.

`make bump-version` updates `Configurations/Project.xcconfig`, not a project file. The release workflows compute tip and release build numbers from that xcconfig and pass telemetry values through configuration, not through source rewriting.

By the end, `supacode.xcodeproj` is deleted from source control and `.gitignore` treats the generated project and workspace as outputs.

## Idempotence and Recovery

`make generate-project` and `mise exec -- tuist install` must be safe to run repeatedly. The Ghostty build script must be fingerprinted and should exit quickly when `.build/ghostty` is already current. If the generated workspace becomes stale or corrupted, the recovery step is to delete `supacode.xcodeproj`, `supacode.xcworkspace`, and `.build/.tuist-generated-stamps`, then rerun `make generate-project`.

Do not delete the checked-in `supacode.xcodeproj` until the generated workspace has already passed `make build-app`, `make test`, and the unsigned archive validation. Once the old project is removed, do not reintroduce it or keep a second project definition around “just in case”. The whole purpose of this migration is to remove that split ownership.

If CI release steps fail after the project is deleted, the safe retry path is to regenerate locally, run the unsigned archive validation, inspect the generated build settings from the workspace, and adjust the workflow override xcconfig rather than editing manifests blindly.

## Artifacts and Notes

These short evidence snippets explain why the plan chooses this design.

Current broken archive shape:

    /tmp/supacode-release-tip-check/supacode.xcarchive/Products/Applications/supacode.app
    /tmp/supacode-release-tip-check/supacode.xcarchive/Products/usr/local/bin/supacode

Current export failure:

    error: exportArchive exportOptionsPlist error for key "method" expected one {} but found developer-id

Current CLI install contract:

    Bundle.main.resourceURL?
      .appending(path: "bin/supacode", directoryHint: .notDirectory)

Desired target graph:

    GhosttyKit     -> foreignBuild output under .build/ghostty
    supacode-cli   -> command-line tool, SKIP_INSTALL = YES
    supacode       -> app target that copies Ghostty resources and supacode-cli into the bundle
    supacodeTests  -> unit tests hosted by the app

## Interfaces and Dependencies

`Project.swift` must define the build graph and hide packaging policy from callers. The `GhosttyKit` `foreignBuild` target hides Zig, rsync, modulemap repair, and fingerprinting. The `supacode` app target hides the fact that Ghostty resources and the CLI binary are copied into the bundle after compilation. Callers only depend on the final app product.

`scripts/build-ghostty.sh` must support two interfaces. With `--print-fingerprint`, it prints a stable fingerprint and exits. Without arguments, it ensures `ThirdParty/ghostty` is checked out, builds Ghostty into `.build/ghostty`, normalizes the xcframework module maps, and writes the fingerprint file. Nothing outside that script should know Ghostty’s exact build command.

`Configurations/Project.xcconfig` must own `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `SENTRY_DSN`, `POSTHOG_API_KEY`, and `POSTHOG_HOST`. This file hides version and default configuration values from both the Tuist manifest and the workflows. `make bump-version` should only need to edit this file.

`supacode/App/AppCrashReporting.swift` and `supacode/App/AppTelemetry.swift` must expose `setup()` entry points that read from `Bundle.main.infoDictionary`. Those files hide string parsing and missing-value behavior from `supacode/App/supacodeApp.swift`.

`Makefile` must remain the public developer interface. It should expose `generate-project`, `generate-project-sources`, `build-app`, `run-app`, `archive`, `export-archive`, `test`, `format`, `lint`, `check`, and `bump-version`. A developer should not need to remember the `tuist install` or `tuist generate` sequencing to do everyday work.

`Tuist/Package.swift` must declare every package product directly imported by the app, tests, or CLI, and `Tuist/Package.resolved` must replace the old Xcode-owned resolution file. `Sparkle`, `Sentry`, `PostHog`, and `Kingfisher` should remain frameworks. Point-Free library products should be static frameworks unless an implementation detail forces otherwise.

Change note: 2026-04-14 08:17Z, Codex. Initial plan drafted from direct inspection of `supacode` and `supaterm`. The plan intentionally chooses a minimal Tuist graph and root-level manifests so the migration removes split build ownership and fixes the release-tip archive regression without dragging in unrelated architectural churn.
