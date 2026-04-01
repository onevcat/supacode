import ComposableArchitecture
import Foundation

nonisolated struct RemoteTerminalSession: Equatable, Sendable, Decodable {
  var id: String
  var scope: String
  var reuseKey: String
  var cwd: String
  var updatedAt: String

  private enum CodingKeys: String, CodingKey {
    case id
    case scope
    case reuseKey = "reuse_key"
    case cwd
    case updatedAt = "updated_at"
  }
}

nonisolated struct RemoteTerminalClient {
  var listSessions: @Sendable (URL) async throws -> [RemoteTerminalSession]

  nonisolated static func sessionsURL(for baseURL: URL) -> URL {
    let normalized = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appending(path: "")
    return
      normalized
      .appending(path: "api/v1/terminal/sessions")
      .appending(queryItems: [URLQueryItem(name: "scope", value: RemoteGroupParsing.scope)])
  }
}

extension RemoteTerminalClient: DependencyKey {
  static let liveValue = RemoteTerminalClient(
    listSessions: { baseURL in
      var request = URLRequest(url: sessionsURL(for: baseURL))
      request.setValue("application/json", forHTTPHeaderField: "Accept")

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        throw URLError(.badServerResponse)
      }

      struct Payload: Decodable {
        var sessions: [RemoteTerminalSession]?
      }

      return try JSONDecoder().decode(Payload.self, from: data).sessions ?? []
    }
  )

  static let testValue = RemoteTerminalClient(
    listSessions: { _ in [] }
  )
}

extension DependencyValues {
  var remoteTerminalClient: RemoteTerminalClient {
    get { self[RemoteTerminalClient.self] }
    set { self[RemoteTerminalClient.self] = newValue }
  }
}
