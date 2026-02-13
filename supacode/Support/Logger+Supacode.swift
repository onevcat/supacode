import OSLog

extension Logger {
  static func supacode(_ category: String) -> Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier!, category: category)
  }
}
