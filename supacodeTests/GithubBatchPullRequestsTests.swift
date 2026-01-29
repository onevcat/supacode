import Foundation
import Testing

@testable import supacode

struct GithubBatchPullRequestsTests {
  @Test func mapsGraphQLAliasesToBranches() throws {
    let json = """
    {
      "data": {
        "repository": {
          "branch0": {
            "nodes": [
              {
                "number": 1,
                "title": "Fork PR",
                "state": "OPEN",
                "additions": 1,
                "deletions": 0,
                "isDraft": false,
                "reviewDecision": null,
                "updatedAt": "2025-01-01T00:00:00Z",
                "url": "https://github.com/other/repo/pull/1",
                "headRefName": "feature-a",
                "headRepository": {
                  "name": "repo",
                  "owner": { "login": "other" }
                }
              },
              {
                "number": 2,
                "title": "Primary PR",
                "state": "OPEN",
                "additions": 2,
                "deletions": 1,
                "isDraft": false,
                "reviewDecision": "APPROVED",
                "updatedAt": "2025-01-02T00:00:00Z",
                "url": "https://github.com/octo/repo/pull/2",
                "headRefName": "feature-a",
                "headRepository": {
                  "name": "repo",
                  "owner": { "login": "octo" }
                }
              }
            ]
          },
          "branch1": {
            "nodes": []
          }
        }
      }
    }
    """
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(GithubGraphQLPullRequestResponse.self, from: data)
    let prs = response.pullRequestsByBranch(
      aliasMap: ["branch0": "feature-a", "branch1": "feature-b"],
      owner: "octo",
      repo: "repo"
    )
    #expect(prs["feature-a"]?.number == 2)
    #expect(prs["feature-a"]?.title == "Primary PR")
    #expect(prs["feature-b"] == nil)
  }

  @Test func ignoresForkOnlyMatches() throws {
    let json = """
    {
      "data": {
        "repository": {
          "branch0": {
            "nodes": [
              {
                "number": 9,
                "title": "Fork PR",
                "state": "OPEN",
                "additions": 1,
                "deletions": 0,
                "isDraft": false,
                "reviewDecision": null,
                "updatedAt": "2025-01-01T00:00:00Z",
                "url": "https://github.com/fork/repo/pull/9",
                "headRefName": "feature-a",
                "headRepository": {
                  "name": "repo",
                  "owner": { "login": "fork" }
                }
              }
            ]
          }
        }
      }
    }
    """
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(GithubGraphQLPullRequestResponse.self, from: data)
    let prs = response.pullRequestsByBranch(
      aliasMap: ["branch0": "feature-a"],
      owner: "octo",
      repo: "repo"
    )
    #expect(prs["feature-a"] == nil)
  }
}
