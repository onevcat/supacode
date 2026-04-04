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
  // swiftlint:disable:next closure_body_length
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
      let installDir = installPath.deletingLastPathComponent().path(percentEncoded: false)
      if !fileManager.fileExists(atPath: installDir) {
        do {
          try fileManager.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        } catch {
          throw CLIInstallError(
            message: permissionErrorMessage(for: installDir, action: "create directory", underlying: error)
          )
        }
      }
      let destination = installPath.path(percentEncoded: false)
      if fileManager.fileExists(atPath: destination) {
        let attrs = try? fileManager.attributesOfItem(atPath: destination)
        let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink
        guard isSymlink else {
          throw CLIInstallError(
            message: "A file already exists at \(destination) and is not a symlink. "
              + "Remove it manually before installing: sudo rm \(destination)"
          )
        }
        do {
          try fileManager.removeItem(atPath: destination)
        } catch {
          throw CLIInstallError(
            message: "Could not remove existing symlink at \(destination): \(error.localizedDescription)"
          )
        }
      }
      do {
        try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: bundledPath)
      } catch {
        throw CLIInstallError(
          message: permissionErrorMessage(for: destination, action: "create symlink", underlying: error)
        )
      }
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
      do {
        try fileManager.removeItem(atPath: path)
      } catch {
        throw CLIInstallError(message: "Could not remove \(path): \(error.localizedDescription)")
      }
    }
  )

  static let testValue = CLIInstallClient(
    bundledCLIURL: { nil },
    installationStatus: { _ in .notInstalled },
    install: { _ in },
    uninstall: { _ in }
  )
}

private nonisolated func permissionErrorMessage(for path: String, action: String, underlying: any Error) -> String {
  let nsError = underlying as NSError
  if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
    || nsError.domain == NSPOSIXErrorDomain && nsError.code == 13
  {
    let dir = (path as NSString).deletingLastPathComponent
    return "Permission denied when trying to \(action) at \(path).\n\n"
      + "To fix, run in Terminal:\n"
      + "sudo mkdir -p \(dir) && sudo chown $(whoami) \(dir)"
  }
  return "Could not \(action) at \(path): \(underlying.localizedDescription)"
}

extension DependencyValues {
  var cliInstallClient: CLIInstallClient {
    get { self[CLIInstallClient.self] }
    set { self[CLIInstallClient.self] = newValue }
  }
}
