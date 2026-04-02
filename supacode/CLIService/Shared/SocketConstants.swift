// ProwlShared/SocketConstants.swift
// Shared socket path convention between CLI client and app server.

import Foundation

public enum ProwlSocket {
  /// Environment variable for overriding socket path.
  public static let environmentKey = "PROWL_CLI_SOCKET"

  /// Default Unix domain socket path.
  /// Located in user's temporary directory to avoid permission issues.
  ///
  /// If `PROWL_CLI_SOCKET` is set and not empty, it takes precedence.
  public static var defaultPath: String {
    if let override = ProcessInfo.processInfo.environment[environmentKey], !override.isEmpty {
      return override
    }
    let tmpDir = NSTemporaryDirectory()
    return (tmpDir as NSString).appendingPathComponent("prowl-cli.sock")
  }
}
