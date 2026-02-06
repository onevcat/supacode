import SwiftUI

struct RepoHeaderRow: View {
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
  }
}
