// ProwlCLI/CLIRunner.swift
// Central execution point: send envelope to app, render response.

import ArgumentParser
import Foundation
import ProwlCLIShared

enum CLIRunner {
  /// Execute a command envelope by sending it to the running app
  /// and rendering the response.
  static func execute(_ envelope: CommandEnvelope) throws {
    do {
      let responseData = try SocketTransportClient.send(envelope)
      let decoder = JSONDecoder()
      let response = try decoder.decode(CommandResponse.self, from: responseData)
      OutputRenderer.render(response, mode: envelope.output)
      if !response.ok {
        throw ExitCode.failure
      }
    } catch let error as ExitError {
      OutputRenderer.renderError(
        code: error.code,
        message: error.message,
        command: envelope.command.name,
        mode: envelope.output
      )
      throw ExitCode.failure
    } catch is ExitCode {
      throw ExitCode.failure
    } catch {
      OutputRenderer.renderError(
        code: CLIErrorCode.transportFailed,
        message: error.localizedDescription,
        command: envelope.command.name,
        mode: envelope.output
      )
      throw ExitCode.failure
    }
  }
}
