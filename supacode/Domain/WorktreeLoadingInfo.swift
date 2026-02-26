struct WorktreeLoadingInfo: Hashable {
  let name: String
  let repositoryName: String?
  let state: WorktreeLoadingState
  let statusTitle: String?
  let statusDetail: String?
  let statusCommand: String?
  let statusLines: [String]
}
