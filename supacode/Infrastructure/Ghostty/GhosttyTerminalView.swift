import SwiftUI

private let terminalHostLogger = SupaLogger("TerminalHost")

struct GhosttyTerminalView: NSViewRepresentable {
  let surfaceView: GhosttySurfaceView
  var pinnedSize: CGSize?

  private var hostKind: GhosttySurfaceScrollView.HostKind {
    pinnedSize == nil ? .terminal : .canvas
  }

  func makeNSView(context: Context) -> GhosttySurfaceScrollView {
    let view = GhosttySurfaceScrollView(surfaceView: surfaceView, hostKind: hostKind)
    view.pinnedSize = pinnedSize
    terminalHostLogger.info(
      "[CanvasExit] hostMake wrapper=\(view.debugIdentifier) host=\(hostKind.rawValue) "
        + "surface=\(surfaceView.debugIdentifierForLogging) "
        + "pinned=\(pinnedSize != nil)"
    )
    return view
  }

  func updateNSView(_ view: GhosttySurfaceScrollView, context: Context) {
    view.pinnedSize = pinnedSize
    terminalHostLogger.info(
      "[CanvasExit] hostUpdate wrapper=\(view.debugIdentifier) host=\(hostKind.rawValue) "
        + "surface=\(surfaceView.debugIdentifierForLogging) "
        + "pinned=\(pinnedSize != nil) "
        + "attached=\(view.isSurfaceAttachedToDocumentView)"
    )
    view.ensureSurfaceAttached()
  }
}
