import SwiftUI

struct RepoHeaderRow: View {
  private static let debugHeaderLayers = false
  let name: String
  let isRemoving: Bool
  let tabCount: Int
  var nameTooltip: String?
  var body: some View {
    HStack {
      Text(name)
        .foregroundStyle(.secondary)
        .help(nameTooltip ?? "")
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      if tabCount > 0 {
        Text("\(tabCount)")
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: .capsule)
          .help("\(tabCount) active \(tabCount == 1 ? "tab" : "tabs")")
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

// MARK: - Previews

#Preview("RepoHeaderRow") {
  VStack(alignment: .leading, spacing: 12) {
    RepoHeaderRow(name: "supacode", isRemoving: false, tabCount: 3)
    RepoHeaderRow(name: "ghostty", isRemoving: false, tabCount: 0)
    RepoHeaderRow(name: "removing-repo", isRemoving: true, tabCount: 1)
  }
  .padding()
}
