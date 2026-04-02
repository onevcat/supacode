// ProwlCLI/Transport/SocketTransportClient.swift
// Unix domain socket client for communicating with running Prowl app.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import ProwlCLIShared

enum SocketTransportClient {
  /// Send a command envelope to the Prowl app and receive a response.
  static func send(_ envelope: CommandEnvelope) throws -> Data {
    let socketPath = ProwlSocket.defaultPath

    // Encode request
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let requestData = try encoder.encode(envelope)

    // Create socket
    let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard clientFD >= 0 else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Failed to create socket."
      )
    }
    defer { close(clientFD) }

    // Connect
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
    let copyLen = min(pathBytes.count, maxLen)
    withUnsafeMutableBytes(of: &addr.sun_path) { sunPathPtr in
      for idx in 0..<copyLen {
        sunPathPtr[idx] = pathBytes[idx]
      }
      sunPathPtr[copyLen] = 0
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(clientFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
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
    try withUnsafeBytes(of: &length) { try fdWrite(fildes: clientFD, buffer: $0) }
    try requestData.withUnsafeBytes { try fdWrite(fildes: clientFD, buffer: $0) }

    // Read length-prefixed response
    let responseLengthData = try fdRead(fildes: clientFD, count: 4)
    let responseLength = responseLengthData.withUnsafeBytes {
      UInt32(bigEndian: $0.load(as: UInt32.self))
    }

    guard responseLength > 0, responseLength < 10_000_000 else {
      throw ExitError(
        code: CLIErrorCode.transportFailed,
        message: "Invalid response length from app."
      )
    }

    return try fdRead(fildes: clientFD, count: Int(responseLength))
  }

  // MARK: - Low-level I/O using Darwin/Glibc read/write

  private static func fdWrite(fildes: Int32, buffer: UnsafeRawBufferPointer) throws {
    var offset = 0
    while offset < buffer.count {
      let written = Darwin.write(fildes, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
      guard written > 0 else {
        throw ExitError(code: CLIErrorCode.transportFailed, message: "Socket write failed.")
      }
      offset += written
    }
  }

  private static func fdRead(fildes: Int32, count: Int) throws -> Data {
    var data = Data(capacity: count)
    var remaining = count
    let bufferSize = min(count, 65536)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }
    while remaining > 0 {
      let toRead = min(remaining, bufferSize)
      let bytesRead = Darwin.read(fildes, buffer, toRead)
      guard bytesRead > 0 else {
        throw ExitError(code: CLIErrorCode.transportFailed, message: "Socket read failed.")
      }
      data.append(buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
      remaining -= bytesRead
    }
    return data
  }
}
