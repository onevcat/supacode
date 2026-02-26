import OSLog

nonisolated struct SupaLogger: Sendable {
  private let category: String
  #if !DEBUG
    private let logger: Logger
  #endif

  init(_ category: String) {
    self.category = category
    #if !DEBUG
      self.logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: category)
    #endif
  }

  func debug(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.notice("\(message, privacy: .public)")
    #endif
  }

  func info(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.notice("\(message, privacy: .public)")
    #endif
  }

  func warning(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.warning("\(message, privacy: .public)")
    #endif
  }
}
