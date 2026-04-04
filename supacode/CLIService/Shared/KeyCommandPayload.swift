// ProwlShared/KeyCommandPayload.swift
// Success payload for `prowl key --json` matching key.md contract.

import Foundation

public struct KeyCommandPayload: Codable, Sendable {
  public let requested: KeyRequested
  public let key: KeyInfo
  public let delivery: KeyDelivery
  public let target: KeyTarget

  public init(
    requested: KeyRequested,
    key: KeyInfo,
    delivery: KeyDelivery,
    target: KeyTarget
  ) {
    self.requested = requested
    self.key = key
    self.delivery = delivery
    self.target = target
  }
}

public struct KeyRequested: Codable, Sendable {
  public let token: String
  public let `repeat`: Int

  public init(token: String, repeat: Int) {
    self.token = token
    self.repeat = `repeat`
  }
}

public struct KeyInfo: Codable, Sendable {
  public let normalized: String
  public let category: KeyCategory

  public init(normalized: String, category: KeyCategory) {
    self.normalized = normalized
    self.category = category
  }
}

public enum KeyCategory: String, Codable, Sendable {
  case navigation
  case editing
  case control
}

public struct KeyDelivery: Codable, Sendable {
  public let attempted: Int
  public let delivered: Int
  public let mode: String

  public init(attempted: Int, delivered: Int, mode: String = "keyDownUp") {
    self.attempted = attempted
    self.delivered = delivered
    self.mode = mode
  }
}

public struct KeyTarget: Codable, Sendable {
  public let worktree: KeyTargetWorktree
  public let tab: KeyTargetTab
  public let pane: KeyTargetPane

  public init(worktree: KeyTargetWorktree, tab: KeyTargetTab, pane: KeyTargetPane) {
    self.worktree = worktree
    self.tab = tab
    self.pane = pane
  }
}

public struct KeyTargetWorktree: Codable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let rootPath: String
  public let kind: String

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case path
    case rootPath = "root_path"
    case kind
  }

  public init(id: String, name: String, path: String, rootPath: String, kind: String) {
    self.id = id
    self.name = name
    self.path = path
    self.rootPath = rootPath
    self.kind = kind
  }
}

public struct KeyTargetTab: Codable, Sendable {
  public let id: String
  public let title: String
  public let selected: Bool

  public init(id: String, title: String, selected: Bool) {
    self.id = id
    self.title = title
    self.selected = selected
  }
}

public struct KeyTargetPane: Codable, Sendable {
  public let id: String
  public let title: String
  public let cwd: String?
  public let focused: Bool

  public init(id: String, title: String, cwd: String?, focused: Bool) {
    self.id = id
    self.title = title
    self.cwd = cwd
    self.focused = focused
  }
}

// MARK: - Token Normalization

/// Shared token definitions for the `key` command.
/// Used by CLI for validation and by app for response building.
public enum KeyTokens {
  /// Alias map: accepted aliases → canonical token.
  public static let aliases: [String: String] = [
    "return": "enter",
    "escape": "esc",
    "arrow-up": "up",
    "arrow-down": "down",
    "arrow-left": "left",
    "arrow-right": "right",
    "pgup": "pageup",
    "pgdn": "pagedown",
    "ctrl+c": "ctrl-c",
    "ctrl+d": "ctrl-d",
    "ctrl+l": "ctrl-l",
  ]

  /// All canonical tokens recognized in v1.
  public static let canonical: Set<String> = [
    "enter",
    "esc",
    "tab",
    "backspace",
    "up",
    "down",
    "left",
    "right",
    "pageup",
    "pagedown",
    "home",
    "end",
    "ctrl-c",
    "ctrl-d",
    "ctrl-l",
  ]

  /// Category for each canonical token.
  public static let categories: [String: KeyCategory] = [
    "up": .navigation,
    "down": .navigation,
    "left": .navigation,
    "right": .navigation,
    "pageup": .navigation,
    "pagedown": .navigation,
    "home": .navigation,
    "end": .navigation,
    "tab": .navigation,
    "enter": .editing,
    "backspace": .editing,
    "esc": .control,
    "ctrl-c": .control,
    "ctrl-d": .control,
    "ctrl-l": .control,
  ]

  /// Normalize a user-provided token string to its canonical form.
  /// Returns `nil` if the token is not recognized.
  public static func normalize(_ raw: String) -> String? {
    let lowered = raw.lowercased()
    let resolved = aliases[lowered] ?? lowered
    return canonical.contains(resolved) ? resolved : nil
  }

  /// Get the category for a canonical token.
  public static func category(for canonical: String) -> KeyCategory? {
    categories[canonical]
  }
}
