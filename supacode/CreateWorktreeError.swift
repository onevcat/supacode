import Foundation

struct CreateWorktreeError: Identifiable, Hashable {
  let id: UUID
  let title: String
  let message: String
}
