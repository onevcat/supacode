import ComposableArchitecture
import Foundation

enum CLIInstallStatus: Equatable, Sendable {
  case notInstalled
  case installed(path: String)
  case installedDifferentSource(path: String)
}

struct CLIInstallError: Error, Equatable, Sendable, LocalizedError {
  let message: String

  var errorDescription: String? { message }
}

let cliDefaultInstallPath = URL(fileURLWithPath: "/usr/local/bin/prowl")

struct CLIInstallClient: Sendable {
  var bundledCLIURL: @Sendable () -> URL?
  var installationStatus: @Sendable (_ installPath: URL) -> CLIInstallStatus
  var install: @Sendable (_ installPath: URL) async throws -> Void
  var uninstall: @Sendable (_ installPath: URL) async throws -> Void
}

extension CLIInstallClient: DependencyKey {
  static let liveValue = CLIInstallClient(
    bundledCLIURL: {
      Bundle.main.resourceURL?.appendingPathComponent("prowl-cli/prowl")
    },
    installationStatus: { installPath in
      let fileManager = FileManager.default
      let path = installPath.path(percentEncoded: false)
      guard fileManager.fileExists(atPath: path) else {
        return .notInstalled
      }
      guard let attrs = try? fileManager.attributesOfItem(atPath: path),
        attrs[.type] as? FileAttributeType == .typeSymbolicLink,
        let destination = try? fileManager.destinationOfSymbolicLink(atPath: path)
      else {
        return .installedDifferentSource(path: path)
      }
      let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("prowl-cli/prowl")
      let bundledPath = bundledURL?.path(percentEncoded: false) ?? ""
      if destination == bundledPath {
        return .installed(path: path)
      }
      return .installedDifferentSource(path: path)
    },
    install: { installPath in
      let fileManager = FileManager.default
      guard let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("prowl-cli/prowl") else {
        throw CLIInstallError(message: "Could not locate bundled CLI binary.")
      }
      let bundledPath = bundledURL.path(percentEncoded: false)
      guard fileManager.fileExists(atPath: bundledPath) else {
        throw CLIInstallError(message: "Bundled CLI binary not found at \(bundledPath).")
      }
      let destination = installPath.path(percentEncoded: false)
      if fileManager.fileExists(atPath: destination) {
        let attrs = try? fileManager.attributesOfItem(atPath: destination)
        let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink
        guard isSymlink else {
          throw CLIInstallError(
            message: "A file already exists at \(destination) and is not a symlink. "
              + "Remove it manually before installing."
          )
        }
      }
      try cliSymlinkInstall(source: bundledPath, destination: destination)
    },
    uninstall: { installPath in
      let fileManager = FileManager.default
      let path = installPath.path(percentEncoded: false)
      guard fileManager.fileExists(atPath: path) else {
        throw CLIInstallError(message: "No CLI tool found at \(path).")
      }
      guard let attrs = try? fileManager.attributesOfItem(atPath: path),
        attrs[.type] as? FileAttributeType == .typeSymbolicLink
      else {
        throw CLIInstallError(message: "File at \(path) is not a symlink. Refusing to remove for safety.")
      }
      try cliSymlinkUninstall(path: path)
    }
  )

  static let testValue = CLIInstallClient(
    bundledCLIURL: { nil },
    installationStatus: { _ in .notInstalled },
    install: { _ in },
    uninstall: { _ in }
  )
}

// MARK: - Symlink operations with privilege escalation

/// Attempts to create the CLI symlink. Falls back to osascript privilege escalation on permission failure.
private nonisolated func cliSymlinkInstall(source: String, destination: String) throws {
  let fileManager = FileManager.default
  let dir = (destination as NSString).deletingLastPathComponent

  // Try direct approach first
  do {
    if !fileManager.fileExists(atPath: dir) {
      try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    if fileManager.fileExists(atPath: destination) {
      try fileManager.removeItem(atPath: destination)
    }
    try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: source)
    return
  } catch let error as NSError where isPermissionError(error) {
    // Fall through to privilege escalation
  }

  // Privilege escalation via osascript
  let script = "mkdir -p '\(shellEscape(dir))' && "
    + "rm -f '\(shellEscape(destination))' && "
    + "ln -s '\(shellEscape(source))' '\(shellEscape(destination))'"
  try runPrivileged(script: script)
}

/// Attempts to remove the CLI symlink. Falls back to osascript privilege escalation on permission failure.
private nonisolated func cliSymlinkUninstall(path: String) throws {
  let fileManager = FileManager.default

  do {
    try fileManager.removeItem(atPath: path)
    return
  } catch let error as NSError where isPermissionError(error) {
    // Fall through to privilege escalation
  }

  let script = "rm -f '\(shellEscape(path))'"
  try runPrivileged(script: script)
}

private nonisolated func isPermissionError(_ error: NSError) -> Bool {
  (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError)
    || (error.domain == NSPOSIXErrorDomain && error.code == 13)
}

/// Runs a shell command with administrator privileges via osascript.
private nonisolated func runPrivileged(script: String) throws {
  let osa = Process()
  osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  osa.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
  let pipe = Pipe()
  osa.standardError = pipe
  do {
    try osa.run()
  } catch {
    throw CLIInstallError(message: "Failed to launch authorization prompt: \(error.localizedDescription)")
  }
  osa.waitUntilExit()
  guard osa.terminationStatus == 0 else {
    let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if stderr.contains("User canceled") || stderr.contains("-128") {
      throw CLIInstallError(message: "Installation was canceled.")
    }
    throw CLIInstallError(message: "Installation failed: \(stderr)")
  }
}

private nonisolated func shellEscape(_ value: String) -> String {
  value.replacing("'", with: "'\\''")
}

extension DependencyValues {
  var cliInstallClient: CLIInstallClient {
    get { self[CLIInstallClient.self] }
    set { self[CLIInstallClient.self] = newValue }
  }
}
