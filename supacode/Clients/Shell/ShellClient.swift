import ComposableArchitecture
import Darwin
import Foundation

nonisolated struct ShellClient {
  var run: @Sendable (URL, [String], URL?) async throws -> ShellOutput
  var runLogin: @Sendable (URL, [String], URL?) async throws -> ShellOutput
}

extension ShellClient: DependencyKey {
  static let liveValue = ShellClient(
    run: { executableURL, arguments, currentDirectoryURL in
      try await runProcess(
        executableURL: executableURL,
        arguments: arguments,
        currentDirectoryURL: currentDirectoryURL
      )
    },
    runLogin: { executableURL, arguments, currentDirectoryURL in
      let shellURL = URL(fileURLWithPath: defaultShellPath())
      let execCommand = shellExecCommand(for: shellURL)
      let shellArguments =
        ["-l", "-c", execCommand, "--", executableURL.path(percentEncoded: false)] + arguments
      return try await runProcess(
        executableURL: shellURL,
        arguments: shellArguments,
        currentDirectoryURL: currentDirectoryURL
      )
    }
  )

  static let testValue = ShellClient(
    run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
    runLogin: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
  )
}

extension DependencyValues {
  var shellClient: ShellClient {
    get { self[ShellClient.self] }
    set { self[ShellClient.self] = newValue }
  }
}

nonisolated private func runProcess(
  executableURL: URL,
  arguments: [String],
  currentDirectoryURL: URL?
) async throws -> ShellOutput {
  try await Task.detached {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = (String(bytes: outputData, encoding: .utf8) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = (String(bytes: errorData, encoding: .utf8) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let exitCode = process.terminationStatus
    if exitCode != 0 {
      let command = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")
      throw ShellClientError(command: command, stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
    return ShellOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
  }.value
}

nonisolated private func shellExecCommand(for shellURL: URL) -> String {
  switch shellURL.lastPathComponent {
  case "fish":
    return "exec $argv"
  default:
    return "exec \"$@\""
  }
}

nonisolated private func defaultShellPath() -> String {
  if let env = ProcessInfo.processInfo.environment["SHELL"], !env.isEmpty {
    return env
  }

  var pwd = passwd()
  var result: UnsafeMutablePointer<passwd>?
  let bufSize = sysconf(_SC_GETPW_R_SIZE_MAX)
  let size = bufSize > 0 ? Int(bufSize) : 1024
  var buffer = [CChar](repeating: 0, count: size)
  let lookup = getpwuid_r(getuid(), &pwd, &buffer, buffer.count, &result)
  if lookup == 0, let result, let shell = result.pointee.pw_shell {
    let value = String(cString: shell)
    if !value.isEmpty {
      return value
    }
  }

  return "/bin/zsh"
}
