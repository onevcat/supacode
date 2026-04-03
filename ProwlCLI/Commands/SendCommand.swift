// ProwlCLI/Commands/SendCommand.swift

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import ArgumentParser
import Foundation
import ProwlCLIShared

struct SendCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "send",
    abstract: "Send text input to a terminal pane."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Flag(name: .long, help: "Do not send trailing Enter after text.")
  var noEnter = false

  @Flag(name: .long, help: "Return immediately without waiting for command completion.")
  var noWait = false

  @Option(name: .long, help: "Maximum seconds to wait for completion (1–300, default: 30).")
  var timeout: Int?

  @Argument(help: "Text to send. Alternatively pipe via stdin.")
  var text: String?

  mutating func run() throws {
    try CLIExecution.run(command: "send", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let sel = try selector.resolve()

      if let timeout, (timeout < 1 || timeout > 300) {
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message: "Timeout must be between 1 and 300 seconds."
        )
      }

      // Resolve input source: argv xor stdin
      let inputText: String
      let source: InputSource
      if let argText = text {
        // Check stdin is not also provided
        if isatty(fileno(stdin)) == 0 {
          // stdin has data too — ambiguous
          throw ExitError(
            code: CLIErrorCode.invalidArgument,
            message: "Cannot provide text as both argument and stdin."
          )
        }
        inputText = argText
        source = .argv
      } else if isatty(fileno(stdin)) == 0 {
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
        source = .stdin
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
          trailingEnter: !noEnter,
          source: source,
          wait: !noWait,
          timeoutSeconds: timeout
        ))
      )
      try CLIRunner.execute(envelope)
    }
  }
}
