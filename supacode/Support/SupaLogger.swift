import OSLog

nonisolated struct SupaLogger: Sendable {
  private let category: String
  private let logger: Logger

  init(_ category: String) {
    self.category = category
    self.logger = Logger(
      subsystem: Bundle.main.bundleIdentifier ?? "com.onevcat.prowl",
      category: category
    )
  }

  func debug(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #endif
    logger.notice("\(message, privacy: .public)")
  }

  func info(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #endif
    logger.notice("\(message, privacy: .public)")
  }

  func warning(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #endif
    logger.warning("\(message, privacy: .public)")
  }
}
