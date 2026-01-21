import Foundation

struct OpenRepositoryError: Identifiable, Hashable {
  let id: UUID
  let title: String
  let message: String
}
