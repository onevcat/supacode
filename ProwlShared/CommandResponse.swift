// ProwlShared/CommandResponse.swift
// Structured response from app command service back to CLI.

import Foundation

public struct CommandResponse: Codable, Sendable {
  public let ok: Bool
  public let command: String
  public let schemaVersion: String
  public let data: AnyCodable?
  public let error: CommandError?

  public init(
    ok: Bool,
    command: String,
    schemaVersion: String,
    data: AnyCodable? = nil,
    error: CommandError? = nil
  ) {
    self.ok = ok
    self.command = command
    self.schemaVersion = schemaVersion
    self.data = data
    self.error = error
  }

  enum CodingKeys: String, CodingKey {
    case ok
    case command
    case schemaVersion = "schema_version"
    case data
    case error
  }
}

public struct CommandError: Codable, Sendable {
  public let code: String
  public let message: String
  public let details: AnyCodable?

  public init(code: String, message: String, details: AnyCodable? = nil) {
    self.code = code
    self.message = message
    self.details = details
  }
}

// MARK: - AnyCodable (lightweight type-erased Codable wrapper)

public struct AnyCodable: Codable, Sendable {
  public let value: Any

  public init(_ value: Any) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues(\.value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported AnyCodable type"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodable($0) })
    default:
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Unsupported AnyCodable type: \(type(of: value))"
        )
      )
    }
  }
}
