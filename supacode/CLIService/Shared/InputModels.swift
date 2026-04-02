// ProwlShared/InputModels.swift
// Typed input models matching input.md contract

import Foundation

public struct OpenInput: Codable, Sendable {
  /// Normalized absolute path, or nil for bare `prowl` (bring to front).
  public let path: String?

  public init(path: String? = nil) {
    self.path = path
  }
}

public struct ListInput: Codable, Sendable {
  public init() {}
}

public struct FocusInput: Codable, Sendable {
  public let selector: TargetSelector

  public init(selector: TargetSelector = .none) {
    self.selector = selector
  }
}

public struct SendInput: Codable, Sendable {
  public let selector: TargetSelector
  public let text: String
  public let trailingEnter: Bool

  public init(
    selector: TargetSelector = .none,
    text: String,
    trailingEnter: Bool = true
  ) {
    self.selector = selector
    self.text = text
    self.trailingEnter = trailingEnter
  }
}

public struct KeyInput: Codable, Sendable {
  public let selector: TargetSelector
  public let token: String
  public let repeatCount: Int

  public init(
    selector: TargetSelector = .none,
    token: String,
    repeatCount: Int = 1
  ) {
    self.selector = selector
    self.token = token
    self.repeatCount = repeatCount
  }
}

public struct ReadInput: Codable, Sendable {
  public let selector: TargetSelector
  public let last: Int?

  public init(selector: TargetSelector = .none, last: Int? = nil) {
    self.selector = selector
    self.last = last
  }
}
