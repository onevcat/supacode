import SwiftUI

struct WorktreeLoadingView: View {
  let info: WorktreeLoadingInfo

  var body: some View {
    let actionLabel = info.state == .creating ? "Creating" : "Removing"
    let followup =
      info.state == .creating
      ? "We will open the terminal when it's ready."
      : "We will close the terminal when it's ready."
    VStack {
      ProgressView()
      Text(info.name)
        .font(.headline)
        .monospaced()
      if let repositoryName = info.repositoryName {
        Text("\(actionLabel) worktree in \(repositoryName)")
          .font(.subheadline)
          .monospaced()
          .foregroundStyle(.secondary)
      } else {
        Text("\(actionLabel) worktree...")
          .font(.subheadline)
          .monospaced()
          .foregroundStyle(.secondary)
      }
      Text(followup)
        .font(.subheadline)
        .monospaced()
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
  }
}
