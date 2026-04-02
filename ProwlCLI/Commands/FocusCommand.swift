// ProwlCLI/Commands/FocusCommand.swift

import ArgumentParser

struct FocusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "focus",
    abstract: "Focus a worktree, tab, or pane and bring app to front."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    let sel = try selector.resolve()
    let envelope = CommandEnvelope(
      output: options.outputMode,
      command: .focus(FocusInput(selector: sel))
    )
    try CLIRunner.execute(envelope)
  }
}
