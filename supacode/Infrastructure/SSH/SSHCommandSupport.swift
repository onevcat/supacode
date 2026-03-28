import CryptoKit
import Foundation

nonisolated enum SSHCommandSupport {
  static let connectTimeoutSeconds = 8
  static let serverAliveIntervalSeconds = 5
  static let serverAliveCountMax = 3

  static func connectivityOptions(includeBatchMode: Bool = true) -> [String] {
    var options = [
      "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
      "-o", "ServerAliveInterval=\(serverAliveIntervalSeconds)",
      "-o", "ServerAliveCountMax=\(serverAliveCountMax)",
      "-o", "ControlMaster=auto",
      "-o", "ControlPersist=600",
    ]

    if includeBatchMode {
      options = ["-o", "BatchMode=yes"] + options
    }

    return options
  }

  static func controlSocketPath(
    endpointKey: String,
    temporaryDirectory: String = NSTemporaryDirectory()
  ) -> String {
    let hashData = SHA256.hash(data: Data(endpointKey.utf8))
    let hash = hashData.map { String(format: "%02x", $0) }.joined()
    let preferredPath = "\(NSHomeDirectory())/.prowl/ssh/\(hash)"
    if preferredPath.utf8.count <= 96 {
      return preferredPath
    }

    let tempPath = URL(fileURLWithPath: temporaryDirectory, isDirectory: true)
      .standardizedFileURL
      .path(percentEncoded: false)
    return "\(tempPath)/prowl-ssh-\(String(hash.prefix(16)))"
  }

  static func removingBatchMode(from options: [String]) -> [String] {
    var filtered: [String] = []
    var index = 0
    while index < options.count {
      if index + 1 < options.count,
        options[index] == "-o",
        options[index + 1].lowercased() == "batchmode=yes"
      {
        index += 2
        continue
      }

      filtered.append(options[index])
      index += 1
    }
    return filtered
  }

  static func shellEscape(_ value: String) -> String {
    "'\(value.replacing("'", with: "'\\''"))'"
  }
}
