// ProwlShared/SocketConstants.swift
// Shared socket path convention between CLI client and app server.

import Foundation

public enum ProwlSocket {
  /// Environment variable for overriding socket path.
  public static let environmentKey = "PROWL_CLI_SOCKET"

  /// Environment key used only by CLI process to pass the normalized open path
  /// into app launch arguments during cold launch.
  public static let cliOpenPathEnvironmentKey = "PROWL_CLI_OPEN_PATH"

  /// App launch argument used by CLI open flow to pass the requested path
  /// during cold launch, so app startup can prefer CLI open behavior.
  public static let cliOpenPathArgument = "--prowl-cli-open-path"

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
