// ProwlCLI/Commands/ListCommand.swift

import ArgumentParser
import ProwlCLIShared

struct ListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all worktrees, tabs, and panes."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CLIExecution.run(command: "list", output: options.outputMode) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .list(ListInput())
      )
      try CLIRunner.execute(envelope)
    }
  }
}
