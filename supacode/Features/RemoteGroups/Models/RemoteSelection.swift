import Foundation

nonisolated enum RemoteSelection: Equatable, Codable, Sendable {
  case none
  case overview(endpointID: UUID)
  case group(endpointID: UUID, group: String)
}
