// supacode/CLIService/CommandHandlerProtocol.swift
// Protocol for command handlers on the app side.

import Foundation

/// Each CLI command has a corresponding handler that executes
/// within the app's process context.
protocol CommandHandler {
  /// Execute the command and return a structured response.
  func handle(envelope: CommandEnvelope) async -> CommandResponse
}
