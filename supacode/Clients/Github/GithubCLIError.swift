import Foundation

nonisolated enum GithubCLIError: LocalizedError, Equatable {
  case unavailable
  case commandFailed(String)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "GitHub CLI is unavailable"
    case .commandFailed(let message):
      return message
    }
  }
}
