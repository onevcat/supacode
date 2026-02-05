enum PullRequestStatus {
  static func hasConflicts(mergeable: String?, mergeStateStatus: String?) -> Bool {
    let mergeable = mergeable?.uppercased()
    let mergeStateStatus = mergeStateStatus?.uppercased()
    return mergeable == "CONFLICTING" || mergeStateStatus == "DIRTY"
  }
}
