import SwiftUI

struct RepoHeaderRow: View {
  private static let debugHeaderLayers = false
  let name: String
  let isRemoving: Bool
  var body: some View {
    HStack {
      Text(name)
        .foregroundStyle(.secondary)
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .background {
      if Self.debugHeaderLayers {
        Rectangle()
          .fill(.cyan.opacity(0.18))
          .overlay {
            Rectangle()
              .stroke(.cyan, lineWidth: 1)
          }
      }
    }
  }
}
