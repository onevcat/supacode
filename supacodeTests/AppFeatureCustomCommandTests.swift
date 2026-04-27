import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureCustomCommandTests {
  @Test(.dependencies) func shellScriptCommandCreatesTabWithInput() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Test",
        systemImage: "checkmark.circle",
        command: "swift test",
        execution: .shellScript,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "swift test",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Test",
          customCommandIcon: "checkmark.circle"
        ),
      ],
    )
  }

  @Test(.dependencies) func terminalInputCommandSendsRawCommandText() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Watch",
        systemImage: "terminal",
        command: "pnpm test --watch",
        execution: .terminalInput,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .insertText(worktree, text: "pnpm test --watch")
      ],
    )
  }

  @Test(.dependencies) func splitCommandCreatesSplitWithInput() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Tail",
        systemImage: "doc.text",
        command: "tail -f logs",
        execution: .split,
        splitDirection: .down,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .createSplitWithInput(
          worktree,
          direction: .down,
          input: "tail -f logs",
          autoCloseOnSuccess: false,
          customCommandName: "Tail",
          customCommandIcon: "doc.text"
        ),
      ],
    )
  }

  @Test(.dependencies) func closeOnSuccessFlagIsForwarded() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Build",
        systemImage: "hammer",
        command: "make build",
        execution: .shellScript,
        closeOnSuccess: true,
        shortcut: nil,
      ),
      UserCustomCommand(
        title: "Lint",
        systemImage: "checkmark",
        command: "make lint",
        execution: .split,
        splitDirection: .right,
        closeOnSuccess: true,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.send(.runCustomCommand(1))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "make build",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: true,
          customCommandName: "Build",
          customCommandIcon: "hammer"
        ),
        .createSplitWithInput(
          worktree,
          direction: .right,
          input: "make lint",
          autoCloseOnSuccess: true,
          customCommandName: "Lint",
          customCommandIcon: "checkmark"
        ),
      ],
    )
  }

  @Test func userCustomCommandDecodesWithoutNewFields() throws {
    let legacyJSON = """
      {
        "id": "abc",
        "title": "Legacy",
        "systemImage": "terminal",
        "command": "echo hi",
        "execution": "shellScript"
      }
      """
    let data = Data(legacyJSON.utf8)
    let decoded = try JSONDecoder().decode(UserCustomCommand.self, from: data)
    #expect(decoded.splitDirection == .right)
    #expect(decoded.closeOnSuccess == false)
    #expect(decoded.execution == .shellScript)
  }

  @Test(.dependencies) func invalidCommandIndexDoesNothing() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(sent.value.isEmpty)
  }

  @Test(.dependencies) func supportsCustomCommandBeyondLegacyThreeItemLimit() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "One",
        systemImage: "1.circle",
        command: "echo one",
        execution: .shellScript,
        shortcut: nil,
      ),
      UserCustomCommand(
        title: "Two",
        systemImage: "2.circle",
        command: "echo two",
        execution: .shellScript,
        shortcut: nil,
      ),
      UserCustomCommand(
        title: "Three",
        systemImage: "3.circle",
        command: "echo three",
        execution: .shellScript,
        shortcut: nil,
      ),
      UserCustomCommand(
        title: "Four",
        systemImage: "4.circle",
        command: "echo four",
        execution: .shellScript,
        shortcut: nil,
      ),
      UserCustomCommand(
        title: "Five",
        systemImage: "5.circle",
        command: "echo five",
        execution: .shellScript,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(4))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "echo five",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Five",
          customCommandIcon: "5.circle"
        ),
      ],
    )
  }

  @Test(.dependencies) func defaultTerminalIconIsTreatedAsUnsetForAutoDetection() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Default",
        systemImage: "terminal",
        command: "npm test",
        execution: .shellScript,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    // The model's "terminal" placeholder should not be pinned as a
    // script icon — the auto-detector should remain free to brand the
    // tab from the executed command itself.
    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "npm test",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Default",
          customCommandIcon: nil
        ),
      ],
    )
  }

  @Test(.dependencies) func emptyIconIsTreatedAsUnsetForAutoDetection() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Blank",
        systemImage: "   ",
        command: "swift test",
        execution: .shellScript,
        shortcut: nil,
      ),
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "swift test",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Blank",
          customCommandIcon: nil
        ),
      ],
    )
  }

  @Test(.dependencies) func loadingUserSettingsKeepsCustomCommandsWithoutScript() async {
    let worktree = makeWorktree()
    let settings = UserRepositorySettings(
      customCommands: [
        UserCustomCommand(
          title: "Empty",
          systemImage: "sparkles",
          command: "",
          execution: .shellScript,
          shortcut: nil
        ),
        UserCustomCommand(
          title: "Runnable",
          systemImage: "terminal",
          command: "echo hello",
          execution: .shellScript,
          shortcut: nil
        ),
      ]
    )

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.worktreeUserSettingsLoaded(settings, worktreeID: worktree.id)) {
      $0.selectedCustomCommands = settings.customCommands
      $0.resolvedKeybindings = KeybindingResolver.resolve(
        schema: .appResolverSchema(customCommands: settings.customCommands),
        migratedOverrides:
          LegacyCustomCommandShortcutMigration
          .migrate(commands: settings.customCommands)
          .overrides
      )
    }
  }

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.selection = .worktree(worktree.id)
    return repositoriesState
  }
}
