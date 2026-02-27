import Foundation

nonisolated struct OnevcatRepositorySettings: Codable, Equatable, Sendable {
  static let maxCustomCommands = 3

  var customCommands: [OnevcatCustomCommand]

  static let `default` = OnevcatRepositorySettings(customCommands: [])

  private enum CodingKeys: String, CodingKey {
    case customCommands
  }

  init(customCommands: [OnevcatCustomCommand]) {
    self.customCommands = Self.normalizedCommands(customCommands)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commands = try container.decodeIfPresent([OnevcatCustomCommand].self, forKey: .customCommands) ?? []
    customCommands = Self.normalizedCommands(commands)
  }

  func normalized() -> OnevcatRepositorySettings {
    OnevcatRepositorySettings(customCommands: customCommands)
  }

  static func normalizedCommands(_ commands: [OnevcatCustomCommand]) -> [OnevcatCustomCommand] {
    Array(commands.prefix(maxCustomCommands)).map { $0.normalized() }
  }
}

nonisolated struct OnevcatCustomCommand: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var title: String
  var systemImage: String
  var command: String
  var execution: OnevcatCustomCommandExecution
  var shortcut: OnevcatCustomShortcut?

  init(
    id: String = UUID().uuidString,
    title: String,
    systemImage: String,
    command: String,
    execution: OnevcatCustomCommandExecution,
    shortcut: OnevcatCustomShortcut?
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.command = command
    self.execution = execution
    self.shortcut = shortcut?.normalized()
  }

  static func `default`(index: Int) -> OnevcatCustomCommand {
    OnevcatCustomCommand(
      title: "Command \(index + 1)",
      systemImage: "terminal",
      command: "",
      execution: .shellScript,
      shortcut: nil
    )
  }

  func normalized() -> OnevcatCustomCommand {
    OnevcatCustomCommand(
      id: id,
      title: title,
      systemImage: systemImage,
      command: command,
      execution: execution,
      shortcut: shortcut?.normalized()
    )
  }

  var resolvedTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "Command"
    }
    return trimmed
  }

  var resolvedSystemImage: String {
    let trimmed = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "terminal"
    }
    return trimmed
  }

  var hasRunnableCommand: Bool {
    !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

nonisolated enum OnevcatCustomCommandExecution: String, Codable, CaseIterable, Identifiable, Sendable {
  case shellScript
  case terminalInput

  var id: String { rawValue }

  var title: String {
    switch self {
    case .shellScript:
      return "Shell Script"
    case .terminalInput:
      return "Terminal Input"
    }
  }
}

nonisolated struct OnevcatCustomShortcut: Codable, Equatable, Sendable {
  var key: String
  var modifiers: OnevcatCustomShortcutModifiers

  init(key: String, modifiers: OnevcatCustomShortcutModifiers) {
    self.key = key
    self.modifiers = modifiers
  }

  func normalized() -> OnevcatCustomShortcut {
    let scalar = key.trimmingCharacters(in: .whitespacesAndNewlines).first
    return OnevcatCustomShortcut(
      key: scalar.map { String($0).lowercased() } ?? "",
      modifiers: modifiers
    )
  }

  var isValid: Bool {
    let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalizedKey.count == 1
  }

  var display: String {
    var parts: [String] = []
    if modifiers.command { parts.append("⌘") }
    if modifiers.shift { parts.append("⇧") }
    if modifiers.option { parts.append("⌥") }
    if modifiers.control { parts.append("⌃") }
    parts.append(key.uppercased())
    return parts.joined()
  }
}

nonisolated struct OnevcatCustomShortcutModifiers: Codable, Equatable, Sendable {
  var command: Bool
  var shift: Bool
  var option: Bool
  var control: Bool

  init(command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
    self.command = command
    self.shift = shift
    self.option = option
    self.control = control
  }

  var isEmpty: Bool {
    !command && !shift && !option && !control
  }
}
