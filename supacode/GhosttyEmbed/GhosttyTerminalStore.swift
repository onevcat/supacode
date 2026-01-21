import Foundation
import Observation

@MainActor
@Observable
final class GhosttyTerminalStore {
  private let runtime: GhosttyRuntime
  private var surfaceViews: [String: GhosttySurfaceView] = [:]

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
  }

  func surfaceView(for id: String, workingDirectory: URL?) -> GhosttySurfaceView {
    if let existing = surfaceViews[id] {
      return existing
    }
    let view = GhosttySurfaceView(runtime: runtime, workingDirectory: workingDirectory)
    surfaceViews[id] = view
    return view
  }
}
