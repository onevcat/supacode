import SwiftUI

struct PullRequestChecksPopoverView: View {
  let checks: [GithubPullRequestStatusCheck]
  let pullRequestURL: URL?
  let pullRequestTitle: String?
  private let breakdown: PullRequestCheckBreakdown
  private let sortedChecks: [GithubPullRequestStatusCheck]
  @Environment(\.analyticsClient) private var analyticsClient
  @Environment(\.openURL) private var openURL

  init(checks: [GithubPullRequestStatusCheck], pullRequestURL: URL?, pullRequestTitle: String?) {
    self.checks = checks
    self.pullRequestURL = pullRequestURL
    self.pullRequestTitle = pullRequestTitle
    self.breakdown = PullRequestCheckBreakdown(checks: checks)
    self.sortedChecks = checks.sorted {
      let left = Self.sortRank(for: $0.checkState)
      let right = Self.sortRank(for: $1.checkState)
      if left == right {
        return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
      return left < right
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        if let pullRequestURL {
          Button {
            analyticsClient.capture("github_pr_opened", nil)
            openURL(pullRequestURL)
          } label: {
            Text("\(pullRequestTitle ?? "Open pull request on GitHub") ↗")
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .help("Open pull request on GitHub (\(AppShortcuts.openPullRequest.display))")
          .keyboardShortcut(AppShortcuts.openPullRequest.keyboardShortcut)
          .font(.headline)
        }

        if breakdown.total > 0 {
          HStack {
            PullRequestChecksRingView(breakdown: breakdown)
            Text(breakdown.summaryText)
              .foregroundStyle(.secondary)
          }
          .font(.caption)
        }

        if !sortedChecks.isEmpty {
          Divider()
          VStack(alignment: .leading) {
            ForEach(sortedChecks, id: \.self) { check in
              let style = PullRequestCheckStatusStyle(state: check.checkState)
              HStack {
                Image(systemName: style.symbol)
                  .foregroundStyle(style.color)
                  .accessibilityHidden(true)
                if let url = check.detailsUrl.flatMap(URL.init(string:)) {
                  Button {
                    analyticsClient.capture("github_ci_check_opened", nil)
                    openURL(url)
                  } label: {
                    Text(check.displayName)
                      .lineLimit(1)
                  }
                  .buttonStyle(.plain)
                  .help("Open check details on GitHub")
                } else {
                  Text(check.displayName)
                    .lineLimit(1)
                }
                Spacer()
                Text(style.label)
                  .foregroundStyle(.secondary)
              }
              .font(.caption)
            }
          }
        }
      }
      .padding()
    }
    .frame(minWidth: 260, maxWidth: 840, maxHeight: 720)
  }

  private static func sortRank(for state: GithubPullRequestCheckState) -> Int {
    switch state {
    case .failure:
      return 0
    case .inProgress:
      return 1
    case .expected:
      return 2
    case .skipped:
      return 3
    case .success:
      return 4
    }
  }

}
