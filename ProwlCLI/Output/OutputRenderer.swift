// ProwlCLI/Output/OutputRenderer.swift
// Renders command responses for terminal output.

import Foundation
import ProwlCLIShared

enum OutputRenderer {
  static func render(_ response: CommandResponse, mode: OutputMode) {
    switch mode {
    case .json:
      renderJSON(response)
    case .text:
      renderText(response)
    }
  }

  static func renderError(code: String, message: String, command: String, mode: OutputMode) {
    let response = CommandResponse(
      ok: false,
      command: command,
      schemaVersion: "prowl.cli.\(command).v1",
      error: CommandError(code: code, message: message)
    )
    render(response, mode: mode)
  }

  // MARK: - JSON

  private static func renderJSON(_ response: CommandResponse) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(response),
       let jsonString = String(data: data, encoding: .utf8)
    {
      print(jsonString)
    }
  }

  // MARK: - Text

  private static func renderText(_ response: CommandResponse) {
    if response.ok {
      print("ok: \(response.command)")
    } else if let error = response.error {
      FileHandle.standardError.write(
        Data("error [\(error.code)]: \(error.message)\n".utf8)
      )
    }
  }
}
