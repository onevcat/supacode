// supacode/CLIService/CLISocketServer.swift
// Unix domain socket server that listens for CLI command requests.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

@MainActor
final class CLISocketServer {
  private let router: CLICommandRouter
  private let socketPath: String
  private var serverFD: Int32 = -1
  private var isRunning = false
  private let acceptQueue = DispatchQueue(label: "com.onevcat.prowl.cli-accept", qos: .userInitiated)

  init(router: CLICommandRouter, socketPath: String = ProwlSocket.defaultPath) {
    self.router = router
    self.socketPath = socketPath
  }

  /// Start listening for CLI connections.
  func start() throws {
    // Clean up stale socket file
    unlink(socketPath)

    // Create socket
    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw CLIServiceError.socketCreationFailed
    }

    // Bind
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

    let bindResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }

    guard bindResult == 0 else {
      close(serverFD)
      throw CLIServiceError.bindFailed
    }

    // Listen
    guard listen(serverFD, 5) == 0 else {
      close(serverFD)
      throw CLIServiceError.listenFailed
    }

    isRunning = true

    // Run the blocking accept loop on a dedicated dispatch queue so it does
    // not occupy a Swift cooperative-thread-pool thread (which would starve
    // the concurrency runtime and hang the app – especially during testing).
    let listeningFD = serverFD
    acceptQueue.async { [weak self] in
      Self.acceptLoop(serverFD: listeningFD, server: self)
    }
  }

  /// Stop the server and clean up.
  func stop() {
    isRunning = false
    if serverFD >= 0 {
      close(serverFD)
      serverFD = -1
    }
    unlink(socketPath)
  }

  // MARK: - Accept loop (runs on acceptQueue, NOT in Swift concurrency)

  private nonisolated static func acceptLoop(serverFD: Int32, server: CLISocketServer?) {
    while true {
      let clientFD = Darwin.accept(serverFD, nil, nil)
      guard clientFD >= 0 else {
        // serverFD was closed (stop() called) or an error occurred – exit.
        return
      }
      if let server {
        Task { @MainActor in
          await server.handleClient(clientFD: clientFD)
        }
      } else {
        Darwin.close(clientFD)
      }
    }
  }

  private func handleClient(clientFD: Int32) async {
    defer { Darwin.close(clientFD) }

    do {
      // Read length-prefixed request
      let lengthData = try Self.fdRead(fildes: clientFD, count: 4)
      let length = lengthData.withUnsafeBytes {
        UInt32(bigEndian: $0.load(as: UInt32.self))
      }
      guard length > 0, length < 10_000_000 else { return }

      let requestData = try Self.fdRead(fildes: clientFD, count: Int(length))

      // Decode envelope
      let decoder = JSONDecoder()
      let envelope = try decoder.decode(CommandEnvelope.self, from: requestData)

      // Route to handler
      let response = await router.route(envelope)

      // Encode and send response
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let responseData = try encoder.encode(response)

      var responseLength = UInt32(responseData.count).bigEndian
      try withUnsafeBytes(of: &responseLength) { try Self.fdWrite(fildes: clientFD, buffer: $0) }
      try responseData.withUnsafeBytes { try Self.fdWrite(fildes: clientFD, buffer: $0) }
    } catch {
      // Connection-level errors are silently dropped
    }
  }

  // MARK: - Low-level I/O using Darwin read/write

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
        throw CLIServiceError.readFailed
      }
      data.append(buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
      remaining -= bytesRead
    }
    return data
  }

  private static func fdWrite(fildes: Int32, buffer: UnsafeRawBufferPointer) throws {
    var offset = 0
    while offset < buffer.count {
      let written = Darwin.write(fildes, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
      guard written > 0 else {
        throw CLIServiceError.writeFailed
      }
      offset += written
    }
  }
}

// MARK: - Errors

enum CLIServiceError: Error {
  case socketCreationFailed
  case socketPathTooLong
  case bindFailed
  case listenFailed
  case readFailed
  case writeFailed
}
