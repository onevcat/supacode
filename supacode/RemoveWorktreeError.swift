import Foundation

struct RemoveWorktreeError: Identifiable, Hashable {
    let id: UUID
    let title: String
    let message: String
}
