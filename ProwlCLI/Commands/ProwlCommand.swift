// ProwlCLI/Commands/ProwlCommand.swift
// Root command with bare path entry detection.

import ArgumentParser
import Foundation

struct ProwlCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "prowl",
    abstract: "Control a running Prowl instance from the command line.",
    version: ProwlVersion.current,
    subcommands: [
      OpenCommand.self,
      ListCommand.self,
      FocusCommand.self,
      SendCommand.self,
      KeyCommand.self,
      ReadCommand.self,
    ],
    defaultSubcommand: OpenCommand.self
  )
}

// MARK: - Version

enum ProwlVersion {
  static let current = "1.0.0-dev"
}
