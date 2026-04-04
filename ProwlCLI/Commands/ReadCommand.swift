// ProwlCLI/Commands/ReadCommand.swift

import ArgumentParser
import ProwlCLIShared

struct ReadCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "read",
    abstract: "Read terminal content from a pane."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Number of recent lines to read (omit for snapshot).")
  var last: Int?

  mutating func run() throws {
    try CLIExecution.run(command: "read", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let sel = try selector.resolve()

      if let n = last, n < 1 {
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message: "--last requires a positive integer, got \(n)."
        )
      }

      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .read(ReadInput(selector: sel, last: last))
      )
      try CLIRunner.execute(envelope)
    }
  }
}
