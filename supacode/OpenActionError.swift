import Foundation

struct OpenActionError: Identifiable, Hashable {
  let id: UUID
  let title: String
  let message: String

  init(title: String, message: String) {
    id = UUID()
    self.title = title
    self.message = message
  }
}
