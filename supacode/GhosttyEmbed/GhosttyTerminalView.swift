import SwiftUI

struct GhosttyTerminalView: NSViewRepresentable {
  let surfaceView: GhosttySurfaceView

  func makeNSView(context: Context) -> GhosttySurfaceView {
    surfaceView
  }

  func updateNSView(_ view: GhosttySurfaceView, context: Context) {
    view.updateSurfaceSize()
  }
}
