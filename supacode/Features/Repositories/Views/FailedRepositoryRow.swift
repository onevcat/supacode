import SwiftUI

struct FailedRepositoryRow: View {
  let name: String
  let initials: String
  let path: String
  let showFailure: () -> Void
  let removeRepository: () -> Void

  var body: some View {
    HStack(spacing: 8) {
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
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.headline)
          .ghosttyMonospaced(.headline)
        Text(path)
          .font(.caption)
          .ghosttyMonospaced(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Button("Show load failure", systemImage: "exclamationmark.triangle.fill", action: showFailure)
        .labelStyle(.iconOnly)
        .foregroundStyle(.red)
        .help("Show load failure")
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .contextMenu {
      Button("Remove Repository", action: removeRepository)
        .help("Remove repository ")
    }
    .selectionDisabled(true)
  }
}
