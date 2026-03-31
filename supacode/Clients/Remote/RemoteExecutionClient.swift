import ComposableArchitecture
import Foundation

struct RemoteExecutionClient: Sendable {
  struct Output: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }

  var run: @Sendable (_ profile: SSHHostProfile, _ command: String, _ timeoutSeconds: Int) async throws -> Output
}

extension RemoteExecutionClient: DependencyKey {
  static let liveValue = live()

  static func live(
    shellClient: ShellClient = .liveValue,
    keychainClient: KeychainClient = .liveValue
  ) -> RemoteExecutionClient {
    RemoteExecutionClient(
      run: { profile, command, timeoutSeconds in
        let endpointKey = [profile.host, profile.user, profile.port.map(String.init) ?? "22"]
          .joined(separator: "|")
        let controlPath = SSHCommandSupport.controlSocketPath(endpointKey: endpointKey)
        try SSHCommandSupport.ensureControlSocketDirectory(for: controlPath)

        var options = SSHCommandSupport.connectivityOptions(includeBatchMode: true)
        options += ["-o", "ControlPath=\(controlPath)"]

        if let port = profile.port {
          options += ["-p", "\(port)"]
        }

        let target = profile.user.isEmpty ? profile.host : "\(profile.user)@\(profile.host)"
        let arguments = options + [target, command]
        do {
          if profile.authMethod == .password {
            guard let password = try await keychainClient.loadPassword(profile.id) else {
              throw RemoteExecutionClientError.passwordMissing(profile.id)
            }
            try await bootstrapPasswordControlMaster(
              shellClient: shellClient,
              profile: profile,
              target: target,
              controlPath: controlPath,
              password: password
            )
          }
          let output = try await shellClient.runWithTimeout(
            URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments,
            nil,
            timeoutSeconds: timeoutSeconds
          )
          return Output(stdout: output.stdout, stderr: output.stderr, exitCode: output.exitCode)
        } catch let shellError as ShellClientError {
          return Output(
            stdout: shellError.stdout,
            stderr: shellError.stderr,
            exitCode: shellError.exitCode
          )
        }
      }
    )
  }

  private static func bootstrapPasswordControlMaster(
    shellClient: ShellClient,
    profile: SSHHostProfile,
    target: String,
    controlPath: String,
    password: String
  ) async throws {
    let askpassSupport = try SSHCommandSupport.makeAskpassSupport(password: password)
    defer {
      try? FileManager.default.removeItem(at: askpassSupport.helperURL)
    }

    var arguments = SSHCommandSupport.connectivityOptions(includeBatchMode: false)
    arguments += [
      "-o", "ControlMaster=auto",
      "-o", "ControlPersist=600",
      "-o", "ControlPath=\(controlPath)",
      "-o", "PreferredAuthentications=password,keyboard-interactive",
      "-o", "PubkeyAuthentication=no",
      "-o", "NumberOfPasswordPrompts=1",
      "-o", "BatchMode=no",
    ]

    if let port = profile.port {
      arguments += ["-p", "\(port)"]
    }

    arguments += [target, "exit"]

    _ = try await shellClient.runWithTimeout(
      URL(fileURLWithPath: "/usr/bin/ssh"),
      arguments,
      nil,
      environment: askpassSupport.environment,
      timeoutSeconds: SSHCommandSupport.bootstrapTimeoutSeconds
    )
  }

  static let testValue = RemoteExecutionClient(
    run: { _, _, _ in
      Output(stdout: "", stderr: "", exitCode: 0)
    }
  )
}

extension DependencyValues {
  var remoteExecutionClient: RemoteExecutionClient {
    get { self[RemoteExecutionClient.self] }
    set { self[RemoteExecutionClient.self] = newValue }
  }
}

private enum RemoteExecutionClientError: LocalizedError {
  case passwordMissing(String)

  var errorDescription: String? {
    switch self {
    case .passwordMissing:
      "SSH password is required for this host."
    }
  }
}
