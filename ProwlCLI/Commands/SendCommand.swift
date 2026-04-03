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
  /// Check if stdin has readable data using poll(2) with zero timeout.
  private static func stdinHasData() -> Bool {
    var pfd = pollfd(fd: fileno(stdin), events: Int16(POLLIN), revents: 0)
    return poll(&pfd, 1, 0) > 0 && (pfd.revents & Int16(POLLIN)) != 0
  }

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
      let stdinIsPiped = isatty(fileno(stdin)) == 0 && Self.stdinHasData()
      let inputText: String
      let source: InputSource
      if let argText = text {
        if stdinIsPiped {
          throw ExitError(
            code: CLIErrorCode.invalidArgument,
            message: "Cannot provide text as both argument and stdin."
          )
        }
        inputText = argText
        source = .argv
      } else if stdinIsPiped {
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
