// ProwlCLI/Commands/SendCommand.swift

import ArgumentParser
import Foundation

struct SendCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "send",
    abstract: "Send text input to a terminal pane."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Flag(name: .long, help: "Do not send trailing Enter after text.")
  var noEnter = false

  @Argument(help: "Text to send. Alternatively pipe via stdin.")
  var text: String?

  mutating func run() throws {
    let sel = try selector.resolve()

    // Resolve input source: argv xor stdin
    let inputText: String
    if let argText = text {
      // Check stdin is not also provided
      if !isatty(fileno(stdin)) {
        // stdin has data too — ambiguous
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message: "Cannot provide text as both argument and stdin."
        )
      }
      inputText = argText
    } else if !isatty(fileno(stdin)) {
      // Read from stdin
      guard let stdinData = try? FileHandle.standardInput.readToEnd(),
            let stdinText = String(data: stdinData, encoding: .utf8),
            !stdinText.isEmpty
      else {
        throw ExitError(
          code: CLIErrorCode.emptyInput,
          message: "No input provided via argument or stdin."
        )
      }
      inputText = stdinText
    } else {
      throw ExitError(
        code: CLIErrorCode.emptyInput,
        message: "No input provided. Pass text as argument or pipe via stdin."
      )
    }

    let envelope = CommandEnvelope(
      output: options.outputMode,
      command: .send(SendInput(
        selector: sel,
        text: inputText,
        trailingEnter: !noEnter
      ))
    )
    try CLIRunner.execute(envelope)
  }
}
