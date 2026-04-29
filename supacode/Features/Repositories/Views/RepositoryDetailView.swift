import SwiftUI

struct RepositoryDetailView: View {
  let repository: Repository

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: repository.kind == .git ? "folder.badge.gearshape" : "folder")
        .font(.largeTitle)
        .accessibilityHidden(true)
      RepoDisplayName(
        fallbackName: repository.name,
        repositoryRootURL: repository.rootURL
      )
      .font(.title3.weight(.semibold))
      Text(repository.rootURL.path(percentEncoded: false))
        .font(.subheadline.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      Text(descriptionText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
    .background(Color(nsColor: .windowBackgroundColor))
    .multilineTextAlignment(.center)
  }

  private var descriptionText: String {
    switch repository.kind {
    case .git:
      "Select a worktree to open its terminal and repository tools."
    case .plain:
      "This folder is available in the sidebar. Git-only actions stay hidden."
    }
  }
}
