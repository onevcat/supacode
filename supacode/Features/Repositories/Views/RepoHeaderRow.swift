import SwiftUI

struct RepoHeaderRow: View {
  let name: String
  let initials: String
  let isExpanded: Bool
  let isRemoving: Bool

  var body: some View {
    HStack {
      Image(systemName: "chevron.right")
        .font(.caption)
        .ghosttyMonospaced(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
        .rotationEffect(.degrees(isExpanded ? 90 : 0))
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        .frame(width: 10, alignment: .center)
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.secondary.opacity(0.2))
        Text(initials)
          .font(.caption)
          .ghosttyMonospaced(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: 24, height: 24)
      .clipShape(.rect(cornerRadius: 6, style: .continuous))
      Text(name)
        .font(.headline)
        .ghosttyMonospaced(.headline)
        .foregroundStyle(.primary)
      if isRemoving {
        Text("Removing...")
          .font(.caption)
          .ghosttyMonospaced(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
