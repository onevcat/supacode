import Foundation

struct RemoveRepositoryError: Identifiable, Hashable {
  let id: UUID
  let title: String
  let message: String
}
