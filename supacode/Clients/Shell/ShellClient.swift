import ComposableArchitecture
import Darwin
import Foundation

nonisolated struct ShellClient {
  var run: @Sendable (URL, [String], URL?) async throws -> ShellOutput
  var _runLogin: @Sendable (URL, [String], URL?, Bool) async throws -> ShellOutput

  func runLogin(
    _ executableURL: URL,
    _ arguments: [String],
    _ currentDirectoryURL: URL?,
    log: Bool = true
  ) async throws -> ShellOutput {
    try await _runLogin(executableURL, arguments, currentDirectoryURL, log)
  }
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
    _runLogin: { executableURL, arguments, currentDirectoryURL, log in
      let shellURL = URL(fileURLWithPath: defaultShellPath())
      let execCommand = shellExecCommand(for: shellURL)
      let shellArguments =
        ["-l", "-c", execCommand, "--", executableURL.path(percentEncoded: false)] + arguments
      if log {
        print(
          "[Shell] runLogin\n\tcwd: \(currentDirectoryURL?.path(percentEncoded: false) ?? "nil")\n\tcmd: \(shellURL.path) \(shellArguments.joined(separator: " "))"
        )
      }
      let result = try await runProcess(
        executableURL: shellURL,
        arguments: shellArguments,
        currentDirectoryURL: currentDirectoryURL
      )
      return result
    }
  )

  static let testValue = ShellClient(
    run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
    _runLogin: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
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
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    let outputHandle = outputPipe.fileHandleForReading
    let errorHandle = errorPipe.fileHandleForReading
    try process.run()
    let stdoutTask = Task.detached { outputHandle.readDataToEndOfFile() }
    let stderrTask = Task.detached { errorHandle.readDataToEndOfFile() }
    process.waitUntilExit()
    let outputData = await stdoutTask.value
    let errorData = await stderrTask.value
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
    return "test -f ~/.config/fish/config.fish; and source ~/.config/fish/config.fish >/dev/null 2>&1; exec $argv"
  case "bash":
    return "[ -f ~/.bashrc ] && . ~/.bashrc >/dev/null 2>&1; exec \"$@\""
  default:
    return "[ -f ~/.zshrc ] && . ~/.zshrc >/dev/null 2>&1; exec \"$@\""
  }
}

nonisolated private func defaultShellPath() -> String {
  if let env = ProcessInfo.processInfo.environment["SHELL"], !env.isEmpty {
    print("[Shell] Using SHELL env: \(env)")
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
      print("[Shell] Using passwd shell: \(value)")
      return value
    }
  }

  print("[Shell] Using fallback: /bin/zsh")
  return "/bin/zsh"
}
