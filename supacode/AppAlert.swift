import Foundation

struct AppAlert: Identifiable, Hashable {
  let id: UUID
  let title: String
  let message: String
}
