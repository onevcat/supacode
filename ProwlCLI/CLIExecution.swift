// ProwlCLI/CLIExecution.swift
// Common command execution wrapper for consistent JSON/text error rendering.

import ArgumentParser
import ProwlCLIShared

enum CLIExecution {
  static func run(command: String, output: OutputMode, _ body: () throws -> Void) throws {
    do {
      try body()
    } catch let error as ExitError {
      OutputRenderer.renderError(
        code: error.code,
        message: error.message,
        command: command,
        mode: output
      )
      throw ExitCode.failure
    }
  }
}
