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
      Text(statusLine)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
  }
}
