import Foundation

enum WorktreeDirtCheck {
    nonisolated static func isDirty(statusOutput: String) -> Bool {
        !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
