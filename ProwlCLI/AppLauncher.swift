// ProwlCLI/AppLauncher.swift
// Launches Prowl.app when CLI detects the app is not running, then waits
// for the CLI socket to become available.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import ProwlCLIShared

enum AppLauncher {
  /// Maximum time to wait for the socket after launching the app.
  private static let socketTimeoutSeconds: TimeInterval = 15
  /// Interval between socket availability checks.
  private static let pollIntervalSeconds: TimeInterval = 0.25

  /// Check whether the CLI socket is currently connectable.
  static func isSocketAvailable() -> Bool {
    canConnect(to: ProwlSocket.defaultPath)
  }

  /// Ensure the app is running and the socket is ready.
  /// Returns `true` only when the app was not running and had to be launched.
  ///
  /// When `PROWL_CLI_SOCKET` is set (e.g. integration tests), auto-launch is
  /// disabled — the caller controls the socket endpoint.
  static func ensureAppRunning() throws -> Bool {
    // If a custom socket path is set, skip auto-launch entirely.
    if let override = ProcessInfo.processInfo.environment[ProwlSocket.environmentKey],
       !override.isEmpty
    {
      return false
    }

    // Fast path: socket file exists and is connectable.
    if isSocketAvailable() {
      return false
    }

    // Socket not available — check if the app process is running.
    if isAppProcessRunning() {
      // App is running but socket isn't ready yet. Wait without launching.
      try waitForSocket()
      return false
    }

    // App is genuinely not running. Launch and wait.
    try launchApp()
    try waitForSocket()
    return true
  }

  // MARK: - Process detection

  /// Check whether a Prowl process is currently running via `pgrep`.
  private static func isAppProcessRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", "Prowl"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return false
    }
    return process.terminationStatus == 0
  }

  // MARK: - App launch

  private static func launchApp() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Prowl"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw ExitError(
        code: CLIErrorCode.launchFailed,
        message: "Failed to launch Prowl: \(error.localizedDescription)"
      )
    }
    guard process.terminationStatus == 0 else {
      throw ExitError(
        code: CLIErrorCode.launchFailed,
        message: "Failed to launch Prowl (exit code \(process.terminationStatus))."
      )
    }
  }

  // MARK: - Socket readiness

  private static func waitForSocket() throws {
    let socketPath = ProwlSocket.defaultPath
    let deadline = Date().addingTimeInterval(socketTimeoutSeconds)
    while Date() < deadline {
      if canConnect(to: socketPath) {
        return
      }
      Thread.sleep(forTimeInterval: pollIntervalSeconds)
    }
    throw ExitError(
      code: CLIErrorCode.launchFailed,
      message: "Prowl CLI socket did not become available within \(Int(socketTimeoutSeconds))s."
    )
  }

  private static func canConnect(to socketPath: String) -> Bool {
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { return false }
    defer { close(socketFD) }

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

    let result = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    return result == 0
  }
}
