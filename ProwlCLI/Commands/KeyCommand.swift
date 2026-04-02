// ProwlCLI/Commands/KeyCommand.swift

import ArgumentParser

struct KeyCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "key",
    abstract: "Send a key event to a terminal pane."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Number of times to repeat the key (1-100).")
  var `repeat`: Int = 1

  @Argument(help: "Key token (e.g. enter, esc, tab, ctrl-c, up, down).")
  var token: String

  mutating func run() throws {
    let sel = try selector.resolve()

    guard (1...100).contains(self.repeat) else {
      throw ExitError(
        code: CLIErrorCode.invalidRepeat,
        message: "Repeat count must be between 1 and 100, got \(self.repeat)."
      )
    }

    let normalized = token.lowercased()

    let envelope = CommandEnvelope(
      output: options.outputMode,
      command: .key(KeyInput(
        selector: sel,
        token: normalized,
        repeatCount: self.repeat
      ))
    )
    try CLIRunner.execute(envelope)
  }
}
