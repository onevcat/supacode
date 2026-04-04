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
          throw CLIInstallError(message: "Could not create directory \(installDir): \(error.localizedDescription)")
        }
      }
      let destination = installPath.path(percentEncoded: false)
      if fileManager.fileExists(atPath: destination) {
        do {
          try fileManager.removeItem(atPath: destination)
        } catch {
          throw CLIInstallError(
            message: "Could not remove existing file at \(destination): \(error.localizedDescription)"
          )
        }
      }
      do {
        try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: bundledPath)
      } catch {
        throw CLIInstallError(
          message: "Could not create symlink at \(destination): \(error.localizedDescription)"
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

extension DependencyValues {
  var cliInstallClient: CLIInstallClient {
    get { self[CLIInstallClient.self] }
    set { self[CLIInstallClient.self] = newValue }
  }
}
