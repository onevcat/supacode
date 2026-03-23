import SwiftUI
import YiTong

struct GitLogWindowContentView: View {
  var state: GitLogWindowState
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @AppStorage("diffViewStyle") private var diffStyleRaw = DiffStyle.split.rawValue

  private var diffStyle: DiffStyle {
    DiffStyle(rawValue: diffStyleRaw) ?? .split
  }

  private var selectedCommitID: Binding<String?> {
    Binding(
      get: { state.selectedCommit?.id },
      set: { id in
        if let id, let commit = state.commits.first(where: { $0.id == id }) {
          state.selectCommit(commit)
        }
      },
    )
  }

  private var selectedFileID: Binding<String?> {
    Binding(
      get: { state.selectedFile?.id },
      set: { id in
        if let id, let file = state.commitFiles.first(where: { $0.id == id }) {
          state.selectFile(file)
        }
      },
    )
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      commitListSidebar
        .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 500)
    } detail: {
      commitDetail
    }
    .focusedSceneValue(\.toggleLeftSidebarAction, toggleSidebar)
    .toolbar(id: "gitLogToolbar") {
      ToolbarItem(id: "sidebarToggle", placement: .navigation) {
        Button {
          toggleSidebar()
        } label: {
          Image(systemName: "sidebar.left")
            .accessibilityLabel("Toggle Sidebar")
        }
        .help("Toggle Sidebar (\(AppShortcuts.toggleLeftSidebar.display))")
      }
      ToolbarItem(id: "diffStyle", placement: .primaryAction) {
        Picker("Diff Style", selection: $diffStyleRaw) {
          Image(systemName: "square.split.2x1")
            .accessibilityLabel("Split")
            .tag(DiffStyle.split.rawValue)
            .help("Split")
          Image(systemName: "text.justify.left")
            .accessibilityLabel("Unified")
            .tag(DiffStyle.unified.rawValue)
            .help("Unified")
        }
        .pickerStyle(.segmented)
        .help("Diff Style")
      }
    }
  }

  private func toggleSidebar() {
    withAnimation {
      columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
    }
  }

  // MARK: - Commit List

  private var commitListSidebar: some View {
    List(selection: selectedCommitID) {
      ForEach(state.commits) { commit in
        CommitRowView(commit: commit)
          .tag(commit.id)
      }
      if state.hasMoreCommits {
        ProgressView()
          .frame(maxWidth: .infinity, alignment: .center)
          .onAppear { state.loadMore() }
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if state.isLoadingCommits && state.commits.isEmpty {
        ProgressView()
      } else if !state.isLoadingCommits && state.commits.isEmpty {
        ContentUnavailableView(
          "No Commits",
          systemImage: "clock",
          description: Text("No commit history found"),
        )
      }
    }
  }

  // MARK: - Commit Detail

  private var commitDetail: some View {
    Group {
      if let commit = state.selectedCommit {
        VStack(spacing: 0) {
          commitHeader(commit)
          Divider()
          commitDiffArea
        }
      } else if state.isLoadingCommits {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Select a Commit",
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
          description: Text("Choose a commit from the sidebar to view details"),
        )
      }
    }
  }

  private func commitHeader(_ commit: GitLogCommit) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(commit.subject)
        .font(.headline)
        .lineLimit(2)
      HStack(spacing: 8) {
        Text(commit.shortHash)
          .font(.caption)
          .monospaced()
          .foregroundStyle(.secondary)
        Text(commit.authorName)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(commit.authorDate, style: .relative)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      if !commit.body.isEmpty, commit.body != commit.subject {
        let bodyWithoutSubject =
          commit.body.hasPrefix(commit.subject)
          ? String(commit.body.dropFirst(commit.subject.count)).trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          : commit.body
        if !bodyWithoutSubject.isEmpty {
          Text(bodyWithoutSubject)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(5)
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var commitDiffArea: some View {
    if state.commitFiles.isEmpty && state.isLoadingDetail {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if state.commitFiles.isEmpty {
      ContentUnavailableView(
        "No Changes",
        systemImage: "checkmark.circle",
        description: Text("This commit has no file changes"),
      )
    } else {
      HSplitView {
        fileList
          .frame(minWidth: 180, idealWidth: 220, maxWidth: 350)
        diffDetail
      }
    }
  }

  private var fileList: some View {
    List(selection: selectedFileID) {
      ForEach(state.commitFiles) { file in
        CommitFileRowView(file: file)
          .tag(file.id)
      }
    }
    .listStyle(.sidebar)
  }

  private var diffDetail: some View {
    Group {
      if let document = state.diffDocument {
        DiffView(
          document: document,
          configuration: DiffConfiguration(
            style: diffStyle,
            showsFileHeaders: false,
          ),
        )
      } else if state.isLoadingDetail {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Select a File",
          systemImage: "doc.text",
          description: Text("Choose a file to view changes"),
        )
      }
    }
  }
}

// MARK: - Commit Row

private struct CommitRowView: View {
  let commit: GitLogCommit

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(commit.subject)
        .font(.body)
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(commit.shortHash)
          .font(.caption)
          .monospaced()
          .foregroundStyle(.secondary)
        Text(commit.authorName)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(commit.authorDate, style: .relative)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Commit File Row

private struct CommitFileRowView: View {
  let file: DiffChangedFile

  var body: some View {
    HStack(spacing: 6) {
      Text(file.statusSymbol)
        .font(.caption)
        .monospaced()
        .foregroundStyle(file.status.color)
        .frame(width: 14, alignment: .center)
      VStack(alignment: .leading, spacing: 1) {
        Text(file.displayName)
          .font(.body)
          .lineLimit(1)
        if !file.directoryPath.isEmpty {
          Text(file.directoryPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }
    }
  }
}
