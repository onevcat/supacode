import SwiftUI

struct WorktreeLoadingView: View {
  let info: WorktreeLoadingInfo

  var body: some View {
    let actionLabel = info.state == .creating ? "Creating" : "Removing"
    let fallbackStatus =
      if let repositoryName = info.repositoryName {
        "\(actionLabel) worktree in \(repositoryName)"
      } else {
        "\(actionLabel) worktree..."
      }
    let statusLine = info.statusDetail ?? info.statusTitle ?? fallbackStatus
    VStack {
      ProgressView()
      Text(info.name)
        .font(.headline)
      if info.statusLines.isEmpty {
        Text(statusLine)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(info.statusLines.enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .frame(maxWidth: 560, maxHeight: 380)
      }
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
  }
}
