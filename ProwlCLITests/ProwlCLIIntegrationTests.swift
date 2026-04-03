#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import ProwlCLIShared
import XCTest

final class ProwlCLIIntegrationTests: XCTestCase {
  private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testHelpAndVersionSmoke() throws {
    let version = try runProwl(args: ["--version"])
    XCTAssertEqual(version.exitCode, 0)
    XCTAssertTrue(version.stdout.contains("1.0.0-dev"))

    let help = try runProwl(args: ["--help"])
    XCTAssertEqual(help.exitCode, 0)
    XCTAssertTrue(help.stdout.contains("USAGE:"))
  }

  func testListReturnsAppNotRunningWhenSocketUnavailable() throws {
    let socketPath = temporarySocketPath(suffix: "app-not-running")
    let result = try runProwl(
      args: ["list", "--json"],
      environment: [ProwlSocket.environmentKey: socketPath]
    )

    XCTAssertNotEqual(result.exitCode, 0)
    let payload = try jsonObject(from: result.stdout)
    XCTAssertEqual(payload["ok"] as? Bool, false)
    let error = try XCTUnwrap(payload["error"] as? [String: Any])
    XCTAssertEqual(error["code"] as? String, CLIErrorCode.appNotRunning)
  }

  func testOpenCommandRoundTripsOverSocket() throws {
    let socketPath = temporarySocketPath(suffix: "open")
    let response = try CommandResponse(
      ok: true,
      command: "open",
      schemaVersion: "prowl.cli.open.v1",
      data: RawJSON(encoding: OpenPayload(
        resolution: "exact-root",
        broughtToFront: true
      ))
    )

    let (requestData, result) = try runWithMockServer(
      socketPath: socketPath,
      response: response,
      args: ["open", ".", "--json"]
    )

    XCTAssertEqual(result.exitCode, 0)
    let envelope = try JSONDecoder().decode(CommandEnvelope.self, from: requestData)
    if case .open(let input) = envelope.command {
      let openedPath = try XCTUnwrap(input.path)
      XCTAssertEqual(
        URL(fileURLWithPath: openedPath).resolvingSymlinksInPath().path,
        repoRoot.resolvingSymlinksInPath().path
      )
    } else {
      XCTFail("Expected open command envelope")
    }

    let payload = try jsonObject(from: result.stdout)
    XCTAssertEqual(payload["ok"] as? Bool, true)
    XCTAssertEqual(payload["command"] as? String, "open")
  }

  func testFocusCommandRoundTripsOverSocket() throws {
    let socketPath = temporarySocketPath(suffix: "focus")
    let response = CommandResponse(
      ok: true,
      command: "focus",
      schemaVersion: "prowl.cli.focus.v1"
    )

    let (requestData, result) = try runWithMockServer(
      socketPath: socketPath,
      response: response,
      args: ["focus", "--pane", "pane-123", "--json"]
    )

    XCTAssertEqual(result.exitCode, 0)
    let envelope = try JSONDecoder().decode(CommandEnvelope.self, from: requestData)
    if case .focus(let input) = envelope.command {
      XCTAssertEqual(input.selector, .pane("pane-123"))
    } else {
      XCTFail("Expected focus command envelope")
    }

    let payload = try jsonObject(from: result.stdout)
    XCTAssertEqual(payload["ok"] as? Bool, true)
    XCTAssertEqual(payload["command"] as? String, "focus")
  }

  // MARK: - Helpers

  private func runWithMockServer(
    socketPath: String,
    response: CommandResponse,
    args: [String]
  ) throws -> (Data, CommandResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let responseData = try encoder.encode(response)
    let server = try MockSocketServer(socketPath: socketPath, responseData: responseData)
    try server.start()

    let result = try runProwl(
      args: args,
      environment: [ProwlSocket.environmentKey: socketPath]
    )

    let requestData = try XCTUnwrap(server.waitForRequest(timeout: 2.0), "No request received by mock server")
    return (requestData, result)
  }

  private func runProwl(
    args: [String],
    environment: [String: String] = [:]
  ) throws -> CommandResult {
    let binaryPath = try ensureProwlBinary()
    var mergedEnvironment = ProcessInfo.processInfo.environment
    for (key, value) in environment {
      mergedEnvironment[key] = value
    }
    return try runProcess(
      executable: binaryPath,
      arguments: args,
      currentDirectory: repoRoot.path,
      environment: mergedEnvironment
    )
  }

  private func ensureProwlBinary() throws -> String {
    let candidates = [
      repoRoot.appendingPathComponent(".build/debug/prowl").path,
      repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/prowl").path,
      repoRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/prowl").path,
    ]

    if let existing = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
      return existing
    }

    throw NSError(
      domain: "ProwlCLITests",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Could not find prowl binary. Checked: \(candidates.joined(separator: ", "))",
      ]
    )
  }

  private func runProcess(
    executable: String,
    arguments: [String],
    currentDirectory: String,
    environment: [String: String]? = nil
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
    if let environment {
      process.environment = environment
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
  }

  private func jsonObject(from text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func temporarySocketPath(suffix: String) -> String {
    let uuid = UUID().uuidString.lowercased()
    let filename = "prowl-cli-\(suffix)-\(uuid).sock"
    return (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
  }
}

private struct OpenPayload: Encodable {
  let resolution: String

  enum CodingKeys: String, CodingKey {
    case resolution
    case broughtToFront = "brought_to_front"
  }

  let broughtToFront: Bool
}

private struct CommandResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

private final class MockSocketServer: @unchecked Sendable {
  private let socketPath: String
  private let responseData: Data

  private var serverFD: Int32 = -1
  private var receivedRequestData: Data?
  private let lock = NSLock()
  private let requestSemaphore = DispatchSemaphore(value: 0)

  init(socketPath: String, responseData: Data) throws {
    self.socketPath = socketPath
    self.responseData = responseData
  }

  deinit {
    if serverFD >= 0 {
      close(serverFD)
    }
    unlink(socketPath)
  }

  func start() throws {
    unlink(socketPath)

    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw MockSocketError.socketCreateFailed
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(socketPath.utf8)
    let maxLength = MemoryLayout.size(ofValue: addr.sun_path) - 1
    let copyLength = min(pathBytes.count, maxLength)

    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
      for index in 0..<copyLength {
        buffer[index] = pathBytes[index]
      }
      buffer[copyLength] = 0
    }

    let bindResult = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPointer in
        bind(serverFD, addrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }

    guard bindResult == 0 else {
      throw MockSocketError.bindFailed
    }

    guard listen(serverFD, 1) == 0 else {
      throw MockSocketError.listenFailed
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let clientFD = accept(self.serverFD, nil, nil)
      guard clientFD >= 0 else { return }
      defer { close(clientFD) }

      do {
        let lengthData = try self.readExact(fd: clientFD, count: 4)
        let bodyLength = lengthData.withUnsafeBytes {
          UInt32(bigEndian: $0.load(as: UInt32.self))
        }
        let body = try self.readExact(fd: clientFD, count: Int(bodyLength))

        self.lock.lock()
        self.receivedRequestData = body
        self.lock.unlock()
        self.requestSemaphore.signal()

        var responseLength = UInt32(self.responseData.count).bigEndian
        try withUnsafeBytes(of: &responseLength) { lengthBytes in
          try self.writeAll(fd: clientFD, bytes: lengthBytes)
        }
        try self.responseData.withUnsafeBytes { bytes in
          try self.writeAll(fd: clientFD, bytes: bytes)
        }
      } catch {
        self.requestSemaphore.signal()
      }
    }
  }

  func waitForRequest(timeout: TimeInterval) -> Data? {
    let result = requestSemaphore.wait(timeout: .now() + timeout)
    guard result == .success else { return nil }

    lock.lock()
    defer { lock.unlock() }
    return receivedRequestData
  }

  private func readExact(fd: Int32, count: Int) throws -> Data {
    var data = Data(capacity: count)
    var remaining = count
    let bufferSize = min(count, 65536)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }

    while remaining > 0 {
      let toRead = min(remaining, bufferSize)
      let readCount = Darwin.read(fd, buffer, toRead)
      guard readCount > 0 else {
        throw MockSocketError.readFailed
      }
      data.append(buffer.assumingMemoryBound(to: UInt8.self), count: readCount)
      remaining -= readCount
    }

    return data
  }

  private func writeAll(fd: Int32, bytes: UnsafeRawBufferPointer) throws {
    var offset = 0
    while offset < bytes.count {
      let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
      guard written > 0 else {
        throw MockSocketError.writeFailed
      }
      offset += written
    }
  }
}

private enum MockSocketError: Error {
  case socketCreateFailed
  case bindFailed
  case listenFailed
  case readFailed
  case writeFailed
}
