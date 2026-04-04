// ProwlCLI/Commands/KeyCommand.swift

import ArgumentParser
import Foundation
import ProwlCLIShared

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
    try CLIExecution.run(command: "key", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let sel = try selector.resolve()

      guard (1...100).contains(self.repeat) else {
        throw ExitError(
          code: CLIErrorCode.invalidRepeat,
          message: "Repeat count must be between 1 and 100, got \(self.repeat)."
        )
      }

      let rawToken = token.trimmingCharacters(in: .whitespaces)

      guard let normalized = KeyTokens.normalize(rawToken) else {
        throw ExitError(
          code: CLIErrorCode.unsupportedKey,
          message: "The key token '\(rawToken.lowercased())' is not supported in v1."
        )
      }

      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .key(KeyInput(
          selector: sel,
          rawToken: rawToken,
          token: normalized,
          repeatCount: self.repeat
        ))
      )
      try CLIRunner.execute(envelope)
    }
  }
}
