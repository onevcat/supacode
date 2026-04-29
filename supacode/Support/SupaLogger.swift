import OSLog

nonisolated struct SupaLogger: Sendable {
  private let category: String
  #if !DEBUG
    private let logger: Logger
  #endif
  /// Signposter for emitting `os_signpost` intervals/events visible in
  /// Instruments. Signposts are essentially zero-cost when no Instruments
  /// session is attached (a single TLS read), so they are always live —
  /// no DEBUG gating.
  ///
  /// The signposter uses the well-known `"PointsOfInterest"` category
  /// regardless of the logger's own `category` so that intervals and
  /// events automatically surface in Apple's **Points of Interest**
  /// instrument (the discoverable, "just drag it in" track most people
  /// will reach for). The signpost `name:` argument carries the actual
  /// origin (e.g. `"OpenBook.onAppear"`, `"focusSelectedTab"`) so source
  /// granularity is preserved — only the routing category differs from
  /// the regular log channel.
  let signposter: OSSignposter

  init(_ category: String) {
    self.category = category
    let subsystem = Bundle.main.bundleIdentifier ?? "com.onevcat.prowl"
    #if !DEBUG
      self.logger = Logger(subsystem: subsystem, category: category)
    #endif
    self.signposter = OSSignposter(subsystem: subsystem, category: "PointsOfInterest")
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

  /// Wraps `body` in an `os_signpost` interval named `name`. The
  /// interval renders as a labeled bar on the Instruments timeline,
  /// making it trivial to correlate hotspots with hangs/hitches without
  /// post-processing the trace XML.
  func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
    let id = signposter.makeSignpostID()
    let state = signposter.beginInterval(name, id: id)
    defer { signposter.endInterval(name, state) }
    return try body()
  }

  /// Manual begin/end pair for code paths that can't use the closure
  /// form — e.g. inside a TCA reducer case where `inout state` cannot
  /// be captured by a non-escaping closure. The returned `IntervalToken`
  /// is opaque to callers, so they don't have to import `OSLog`
  /// themselves.
  func beginInterval(_ name: StaticString) -> IntervalToken {
    let id = signposter.makeSignpostID()
    let state = signposter.beginInterval(name, id: id)
    return IntervalToken(name: name, state: state)
  }

  func endInterval(_ token: IntervalToken) {
    signposter.endInterval(token.name, token.state)
  }

  /// Emits an instantaneous `os_signpost` event marker — useful for
  /// marking discrete moments (e.g. "user clicked book") without an
  /// associated duration.
  func event(_ name: StaticString) {
    signposter.emitEvent(name)
  }
}

/// Opaque token bundling a signpost name and its interval state so
/// callers can `beginInterval` / `endInterval` without depending on
/// `OSLog` themselves.
struct IntervalToken {
  fileprivate let name: StaticString
  fileprivate let state: OSSignpostIntervalState
}
