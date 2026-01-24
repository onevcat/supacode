import ComposableArchitecture
import SwiftUI

struct WorktreeInfoView: View {
  @Bindable var store: StoreOf<WorktreeInfoFeature>

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
      } else if let snapshot = state.snapshot {
        ScrollView {
          VStack(alignment: .leading) {
            if case .failed(let message) = state.status {
              Text(message)
                .foregroundStyle(.red)
            }

            VStack(alignment: .leading) {
              Text("Local Git Data")
                .font(.headline)

              if case .loading = state.status {
                Text("Refreshing...")
                  .foregroundStyle(.secondary)
              }

              LabeledContent("Branch") {
                Text(snapshot.branchName)
              }

              if snapshot.isDetachedHead {
                LabeledContent("Detached HEAD") {
                  Text("Yes")
                }
              }

              LabeledContent("Default branch") {
                Text(snapshot.defaultBranchName ?? "n/a")
                  .foregroundStyle(snapshot.defaultBranchName == nil ? .secondary : .primary)
              }

              LabeledContent("Ahead/Behind default") {
                Text(aheadBehindText(ahead: snapshot.aheadOfDefault, behind: snapshot.behindDefault))
              }

              LabeledContent("Out of date with default") {
                Text(boolText(snapshot.outOfDateWithDefault))
              }

              LabeledContent("Merge conflict risk") {
                Text(boolText(snapshot.mergeConflictPossible))
              }

              LabeledContent("Tracking branch") {
                Text(snapshot.upstreamBranchName ?? "n/a")
                  .foregroundStyle(snapshot.upstreamBranchName == nil ? .secondary : .primary)
              }

              LabeledContent("Ahead/Behind upstream") {
                Text(aheadBehindText(ahead: snapshot.aheadOfUpstream, behind: snapshot.behindUpstream))
              }

              LabeledContent("Remote branch") {
                Text(boolText(snapshot.remoteBranchExists))
              }

              LabeledContent("Uncommitted changes") {
                Text(snapshot.hasUncommittedChanges ? "Yes" : "No")
              }

              LabeledContent("Staged/Unstaged/Untracked") {
                Text("\(snapshot.stagedChanges)/\(snapshot.unstagedChanges)/\(snapshot.untrackedChanges)")
              }

              LabeledContent("Stashes") {
                Text("\(snapshot.stashCount)")
              }

              LabeledContent("Last commit") {
                if let subject = snapshot.lastCommitSubject {
                  Text(subject)
                } else {
                  Text("n/a")
                    .foregroundStyle(.secondary)
                }
              }

              if let lastCommitDate = snapshot.lastCommitDate {
                LabeledContent("Last commit time") {
                  Text(lastCommitDate, style: .relative)
                }
              }
            }

            VStack(alignment: .leading) {
              Text("GitHub CLI Integrations")
                .font(.headline)

              if let githubError = snapshot.githubError {
                LabeledContent("GitHub CLI") {
                  Text(githubError)
                    .foregroundStyle(.secondary)
                }
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

            VStack(alignment: .leading) {
              Text("Paths")
                .font(.headline)

              LabeledContent("Repository name") {
                Text(snapshot.repositoryName)
              }

              LabeledContent("Repository") {
                Text(snapshot.repositoryPath)
              }

              LabeledContent("Worktree") {
                Text(snapshot.worktreePath)
              }
            }

            if let lastRefresh = state.lastRefresh {
              LabeledContent("Last refreshed") {
                Text(lastRefresh, style: .relative)
              }
              .foregroundStyle(.secondary)
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

private func boolText(_ value: Bool?) -> String {
  switch value {
  case .some(true):
    return "Yes"
  case .some(false):
    return "No"
  case .none:
    return "Unknown"
  }
}

private func aheadBehindText(ahead: Int?, behind: Int?) -> String {
  if let ahead, let behind {
    return "ahead \(ahead) / behind \(behind)"
  }
  return "n/a"
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
