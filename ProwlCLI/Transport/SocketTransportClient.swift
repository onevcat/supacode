// ProwlCLI/Transport/SocketTransportClient.swift
// Unix domain socket client for communicating with running Prowl app.

import Foundation

enum SocketTransportClient {
  /// Send a command envelope to the Prowl app and receive a response.
  /// - Parameter envelope: The command to execute.
  /// - Returns: Raw JSON data from the app.
  static func send(_ envelope: CommandEnvelope) throws -> Data {
    let socketPath = ProwlSocket.defaultPath

    // Encode request
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let requestData = try encoder.encode(envelope)

    // Create socket
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Failed to create socket."
      )
    }
    defer { close(fd) }

    // Connect
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Socket path too long."
      )
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
        for (i, byte) in pathBytes.enumerated() {
          dest[i] = byte
        }
      }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }

    guard connectResult == 0 else {
      throw ExitError(
        code: CLIErrorCode.appNotRunning,
        message: "Cannot connect to Prowl. Is the app running?"
      )
    }

    // Send length-prefixed request: 4-byte big-endian length + JSON payload
    var length = UInt32(requestData.count).bigEndian
    let lengthData = Data(bytes: &length, count: 4)
    try socketWrite(fd: fd, data: lengthData)
    try socketWrite(fd: fd, data: requestData)

    // Read length-prefixed response
    let responseLengthData = try socketRead(fd: fd, count: 4)
    let responseLength = responseLengthData.withUnsafeBytes {
      UInt32(bigEndian: $0.load(as: UInt32.self))
    }

    guard responseLength > 0, responseLength < 10_000_000 else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Invalid response length from app."
      )
    }

    return try socketRead(fd: fd, count: Int(responseLength))
  }

  // MARK: - Helpers

  private static func socketWrite(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let written = Foundation.write(
          fd,
          buffer.baseAddress!.advanced(by: offset),
          buffer.count - offset
        )
        guard written > 0 else {
          throw ExitError(
            code: CLIErrorCode.transportFailed,
            message: "Socket write failed."
          )
        }
        offset += written
      }
    }
  }

  private static func socketRead(fd: Int32, count: Int) throws -> Data {
    var data = Data(capacity: count)
    var remaining = count
    let bufferSize = min(count, 65536)
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while remaining > 0 {
      let toRead = min(remaining, bufferSize)
      let bytesRead = Foundation.read(fd, &buffer, toRead)
      guard bytesRead > 0 else {
        throw ExitError(
          code: CLIErrorCode.transportFailed,
          message: "Socket read failed or connection closed."
        )
      }
      data.append(buffer, count: bytesRead)
      remaining -= bytesRead
    }
    return data
  }
}
