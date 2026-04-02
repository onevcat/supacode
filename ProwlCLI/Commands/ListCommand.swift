// ProwlCLI/Commands/ListCommand.swift

import ArgumentParser

struct ListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all worktrees, tabs, and panes."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    let envelope = CommandEnvelope(
      output: options.outputMode,
      command: .list(ListInput())
    )
    try CLIRunner.execute(envelope)
  }
}
