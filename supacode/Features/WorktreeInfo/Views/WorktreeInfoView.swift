import ComposableArchitecture
import SwiftUI

struct WorktreeInfoView: View {
  @Bindable var store: StoreOf<WorktreeInfoFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    let state = store.state
    Group {
      if state.worktree == nil {
        ContentUnavailableView(
          "No Worktree",
          systemImage: "tray",
          description: Text("Select a worktree to see Git and GitHub status.")
        )
      } else if state.snapshot == nil {
        VStack {
          if case .failed(let message) = state.status {
            Text(message)
              .foregroundStyle(.red)
          } else {
            ProgressView("Refreshing...")
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let snapshot = state.snapshot, let worktree = state.worktree {
        let terminalState = terminalManager.stateIfExists(for: worktree.id)
        ScrollView {
          VStack(alignment: .leading) {
            if case .failed(let message) = state.status {
              Text(message)
                .foregroundStyle(.red)
            }

            VStack(alignment: .leading) {
              Text("Local Git Data")
                .font(.headline)
                .monospaced()

              if case .loading = state.status {
                Text("Refreshing...")
                  .foregroundStyle(.secondary)
              }

              LabeledContent("Repository name") {
                Text(snapshot.repositoryName)
              }

              LabeledContent("Repository path") {
                Text(snapshot.repositoryPath)
              }

              LabeledContent("Worktree path") {
                Text(snapshot.worktreePath)
              }
            }

            VStack(alignment: .leading) {
              Text("GitHub CLI Integrations")
                .font(.headline)
                .monospaced()

              if let githubError = snapshot.githubError {
                LabeledContent("GitHub CLI") {
                  Text(githubError)
                    .foregroundStyle(.secondary)
                }
              }

              LabeledContent("Default branch") {
                Text(snapshot.defaultBranchName ?? "n/a")
                  .foregroundStyle(snapshot.defaultBranchName == nil ? .secondary : .primary)
              }

              if let number = snapshot.pullRequestNumber, let title = snapshot.pullRequestTitle {
                LabeledContent("Pull request") {
                  Text("#\(number) \(title)")
                }
              } else {
                LabeledContent("Pull request") {
                  Text("n/a")
                    .foregroundStyle(.secondary)
                }
              }

              LabeledContent("PR state") {
                Text(prStateText(
                  state: snapshot.pullRequestState,
                  isDraft: snapshot.pullRequestIsDraft,
                  reviewDecision: snapshot.pullRequestReviewDecision
                ))
              }

              if let updatedAt = snapshot.pullRequestUpdatedAt {
                LabeledContent("PR updated") {
                  Text(updatedAt, style: .relative)
                }
              }

              Text("CI")
                .font(.subheadline)
                .monospaced()
                .foregroundStyle(.secondary)

              LabeledContent("Workflow") {
                Text(snapshot.workflowName ?? "n/a")
                  .foregroundStyle(snapshot.workflowName == nil ? .secondary : .primary)
              }

              LabeledContent("Status") {
                Text(ciStatusText(status: snapshot.workflowStatus, conclusion: snapshot.workflowConclusion))
              }

              if let updatedAt = snapshot.workflowUpdatedAt {
                LabeledContent("CI updated") {
                  Text(updatedAt, style: .relative)
                }
              }

              if let ciError = snapshot.ciError {
                LabeledContent("CI status") {
                  Text(ciError)
                    .foregroundStyle(.secondary)
                }
              }
            }

            if let nextRefresh = state.nextRefresh {
              LabeledContent("Next periodic refresh") {
                Text(nextRefresh, style: .relative)
              }
              .foregroundStyle(.secondary)
            }

            if let terminalState {
              WorktreeNotificationsListView(state: terminalState, worktreeName: worktree.name)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private func ciStatusText(status: String?, conclusion: String?) -> String {
  var parts: [String] = []
  if let status, !status.isEmpty {
    parts.append(status)
  }
  if let conclusion, !conclusion.isEmpty {
    parts.append(conclusion)
  }
  if parts.isEmpty {
    return "n/a"
  }
  return parts.joined(separator: " / ")
}

private func prStateText(state: String?, isDraft: Bool, reviewDecision: String?) -> String {
  var parts: [String] = []
  if let state, !state.isEmpty {
    parts.append(state)
  }
  if isDraft {
    parts.append("draft")
  }
  if let reviewDecision, !reviewDecision.isEmpty {
    parts.append(reviewDecision)
  }
  if parts.isEmpty {
    return "n/a"
  }
  return parts.joined(separator: " / ")
}
