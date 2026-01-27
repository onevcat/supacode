import SwiftUI

struct RepoHeaderRow: View {
  let name: String
  let initials: String
  let isExpanded: Bool
  let isRemoving: Bool

  var body: some View {
    HStack {
      Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
        .font(.caption)
        .monospaced()
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.secondary.opacity(0.2))
        Text(initials)
          .font(.caption)
          .monospaced()
          .foregroundStyle(.secondary)
      }
      .frame(width: 24, height: 24)
      .clipShape(.rect(cornerRadius: 6, style: .continuous))
      Text(name)
        .font(.headline)
        .monospaced()
        .foregroundStyle(.primary)
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .monospaced()
          .foregroundStyle(.secondary)
      }
    }
  }
}
