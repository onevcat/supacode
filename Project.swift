import ProjectDescription

let ghosttyBuildRootPath: Path = ".build/ghostty"
let ghosttyXCFrameworkPath: Path = ".build/ghostty/GhosttyKit.xcframework"
let ghosttyResourcesPath: Path = ".build/ghostty/share/ghostty"
let ghosttyTerminfoPath: Path = ".build/ghostty/share/terminfo"
let ghosttyBuildScriptPath: Path = "scripts/build-ghostty.sh"
let verifyGitWtScriptPath: Path = "scripts/verify-git-wt.sh"
let embedGhosttyResourcesScriptPath: Path = "scripts/embed-ghostty-resources.sh"
let embedRuntimeAssetsScriptPath: Path = "scripts/embed-runtime-assets.sh"

func shellScript(_ path: Path) -> String {
  "\"${SRCROOT}/\(path.pathString)\""
}

let ghosttyFingerprintInputScript = """
"${SRCROOT}/\(ghosttyBuildScriptPath.pathString)" --print-fingerprint
"""

let appResources: ResourceFileElements = [
  "supacode/Assets.xcassets",
  "supacode/notification.wav",
]

let appBuildableFolders: [BuildableFolder] = [
  "supacode/App",
  "supacode/Clients",
  "supacode/Commands",
  "supacode/Domain",
  "supacode/Features",
  "supacode/Infrastructure",
  "supacode/Support",
]

let appDependencies: [TargetDependency] = [
  .target(name: "GhosttyKit"),
  .target(name: "supacode-cli"),
  .external(name: "CasePaths"),
  .external(name: "ComposableArchitecture"),
  .external(name: "Dependencies"),
  .external(name: "Kingfisher"),
  .external(name: "PostHog"),
  .external(name: "Sentry"),
  .external(name: "Sharing"),
  .external(name: "Sparkle"),
]

let testDependencies: [TargetDependency] = [
  .target(name: "GhosttyKit"),
  .target(name: "supacode"),
  .external(name: "Clocks"),
  .external(name: "ComposableArchitecture"),
  .external(name: "ConcurrencyExtras"),
  .external(name: "CustomDump"),
  .external(name: "Dependencies"),
  .external(name: "DependenciesTestSupport"),
  .external(name: "IdentifiedCollections"),
  .external(name: "Sharing"),
]

let projectBaseSettings: SettingsDictionary = [
  "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
  "CLANG_ENABLE_MODULES": "YES",
  "CODE_SIGN_STYLE": "Automatic",
  "DEVELOPMENT_TEAM": "9ZLSJ2GN2B",
  "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
  "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
  "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
  "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
  "SWIFT_VERSION": "6.0",
]

let cliBaseSettings: SettingsDictionary = [
  "CODE_SIGNING_ALLOWED": "NO",
  "ENABLE_HARDENED_RUNTIME": "YES",
  "PRODUCT_MODULE_NAME": "supacode_cli",
  "PRODUCT_NAME": "supacode",
  "SKIP_INSTALL": "YES",
  "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
]

let appBaseSettings: SettingsDictionary = [
  "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
  "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
  "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "YES",
  "ENABLE_APP_SANDBOX": "NO",
  "ENABLE_HARDENED_RUNTIME": "YES",
  "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
  "OTHER_LDFLAGS": "$(inherited) -lc++",
  "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
  "SWIFT_EMIT_LOC_STRINGS": "YES",
]

let appDebugSettings: SettingsDictionary = [
  "CODE_SIGN_ENTITLEMENTS": "supacode/supacodeDebug.entitlements",
  "COMPILATION_CACHE_ENABLE_CACHING": "YES",
]

let appReleaseSettings: SettingsDictionary = [
  "CODE_SIGN_ENTITLEMENTS": "supacode/supacode.entitlements",
  "COMPILATION_CACHE_ENABLE_CACHING": "NO",
]

let testBaseSettings: SettingsDictionary = [
  "BUNDLE_LOADER": "$(TEST_HOST)",
  "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
  "SWIFT_EMIT_LOC_STRINGS": "NO",
  "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/supacode.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/supacode",
]

let embedGhosttyResourcesInputPaths: [FileListGlob] = [
  "$(SRCROOT)/\(ghosttyResourcesPath.pathString)",
  "$(SRCROOT)/\(ghosttyTerminfoPath.pathString)",
]

let embedGhosttyResourcesOutputPaths: [Path] = [
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ghostty",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/terminfo",
]

let embedRuntimeAssetsInputPaths: [FileListGlob] = [
  "$(SRCROOT)/Resources/git-wt/wt",
  "$(SRCROOT)/supacode/Resources/Themes/Supacode Light",
  "$(SRCROOT)/supacode/Resources/Themes/Supacode Dark",
  "$(BUILT_PRODUCTS_DIR)/supacode",
  "$(UNINSTALLED_PRODUCTS_DIR)/$(PLATFORM_NAME)/supacode",
]

let embedRuntimeAssetsOutputPaths: [Path] = [
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/git-wt/wt",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Supacode Light",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Supacode Dark",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/bin/supacode",
]

let project = Project(
  name: "supacode",
  settings: .settings(
    base: projectBaseSettings,
    configurations: [
      .debug(name: .debug, xcconfig: "Configurations/Project.xcconfig"),
      .release(name: .release, xcconfig: "Configurations/Project.xcconfig"),
    ],
    defaultSettings: .essential
  ),
  targets: [
    .target(
      name: "supacode-cli",
      destinations: .macOS,
      product: .commandLineTool,
      bundleId: "app.supabit.supacode.cli",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "supacode-cli",
      ],
      dependencies: [
        .external(name: "ArgumentParser"),
      ],
      settings: .settings(
        base: cliBaseSettings,
        defaultSettings: .essential
      )
    ),
    .foreignBuild(
      name: "GhosttyKit",
      destinations: .macOS,
      script: """
        "${SRCROOT}/\(ghosttyBuildScriptPath.pathString)"
        """,
      inputs: [
        .file("mise.toml"),
        .file(ghosttyBuildScriptPath),
        .script(ghosttyFingerprintInputScript),
      ],
      output: .xcframework(path: ghosttyXCFrameworkPath, linking: .static)
    ),
    .target(
      name: "supacode",
      destinations: .macOS,
      product: .app,
      bundleId: "app.supabit.supacode",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .file(path: "supacode/Info.plist"),
      resources: appResources,
      buildableFolders: appBuildableFolders,
      scripts: [
        .pre(
          script: shellScript(verifyGitWtScriptPath),
          name: "Verify git-wt",
          basedOnDependencyAnalysis: false
        ),
        .post(
          script: shellScript(embedGhosttyResourcesScriptPath),
          name: "Embed Ghostty Resources",
          inputPaths: embedGhosttyResourcesInputPaths,
          outputPaths: embedGhosttyResourcesOutputPaths,
          basedOnDependencyAnalysis: false
        ),
        .post(
          script: shellScript(embedRuntimeAssetsScriptPath),
          name: "Embed Runtime Assets",
          inputPaths: embedRuntimeAssetsInputPaths,
          outputPaths: embedRuntimeAssetsOutputPaths,
          basedOnDependencyAnalysis: false
        ),
      ],
      dependencies: appDependencies,
      settings: .settings(
        base: appBaseSettings,
        debug: appDebugSettings,
        release: appReleaseSettings,
        defaultSettings: .essential
      )
    ),
    .target(
      name: "supacodeTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "app.supabit.supacodeTests",
      deploymentTargets: .macOS("26.1"),
      infoPlist: .default,
      buildableFolders: [
        "supacodeTests",
      ],
      dependencies: testDependencies,
      settings: .settings(
        base: testBaseSettings,
        defaultSettings: .essential
      )
    ),
  ],
  additionalFiles: [
    "Configurations/**",
  ],
  resourceSynthesizers: []
)
