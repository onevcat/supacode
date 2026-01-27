import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TerminalSplitTreeView: View {
  let tree: SplitTree<GhosttySurfaceView>
  let action: (Operation) -> Void

  private static let dragType = UTType(exportedAs: "sh.supacode.ghosttySurfaceId")
  private static func dragProvider(for surfaceView: GhosttySurfaceView) -> NSItemProvider {
    let provider = NSItemProvider()
    let data = surfaceView.id.uuidString.data(using: .utf8) ?? Data()
    provider.registerDataRepresentation(
      forTypeIdentifier: dragType.identifier,
      visibility: .all
    ) { completion in
      completion(data, nil)
      return nil
    }
    return provider
  }

  var body: some View {
    if let node = tree.zoomed ?? tree.root {
      SubtreeView(node: node, isRoot: node == tree.root, action: action)
        .id(node.structuralIdentity)
    }
  }

  enum Operation {
    case resize(node: SplitTree<GhosttySurfaceView>.Node, ratio: Double)
    case drop(payloadId: UUID, destinationId: UUID, zone: DropZone)
    case equalize
  }

  struct SubtreeView: View {
    let node: SplitTree<GhosttySurfaceView>.Node
    var isRoot: Bool = false
    let action: (Operation) -> Void

    var body: some View {
      switch node {
      case .leaf(let leafView):
        LeafView(surfaceView: leafView, isSplit: !isRoot, action: action)
      case .split(let split):
        let splitViewDirection: SplitView<SubtreeView, SubtreeView>.Direction =
          switch split.direction {
          case .horizontal: .horizontal
          case .vertical: .vertical
          }
        SplitView(
          splitViewDirection,
          .init(
            get: {
              CGFloat(split.ratio)
            },
            set: {
              action(.resize(node: node, ratio: Double($0)))
            }),
          dividerColor: .secondary,
          resizeIncrements: .init(width: 1, height: 1),
          left: {
            SubtreeView(node: split.left, action: action)
          },
          right: {
            SubtreeView(node: split.right, action: action)
          },
          onEqualize: {
            action(.equalize)
          }
        )
      }
    }
  }

  struct LeafView: View {
    let surfaceView: GhosttySurfaceView
    let isSplit: Bool
    let action: (Operation) -> Void

    @State private var dropState: DropState = .idle

    var body: some View {
      GeometryReader { geometry in
        GhosttyTerminalView(surfaceView: surfaceView)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .top) {
            GhosttySurfaceProgressOverlay(state: surfaceView.bridge.state)
          }
          .overlay(alignment: .topTrailing) {
            if surfaceView.bridge.state.searchNeedle != nil {
              GhosttySurfaceSearchOverlay(surfaceView: surfaceView)
            }
          }
          .overlay(alignment: .top) {
            if isSplit {
              DragHandle(surfaceView: surfaceView)
            }
          }
          .background {
            Color.clear
              .contentShape(.rect)
              .onDrop(
                of: [TerminalSplitTreeView.dragType],
                delegate: SplitDropDelegate(
                  dropState: $dropState,
                  viewSize: geometry.size,
                  destinationId: surfaceView.id,
                  action: action
                ))
          }
          .overlay {
            if case .dropping(let zone) = dropState {
              DropOverlayView(zone: zone, size: geometry.size)
                .allowsHitTesting(false)
            }
          }
      }
    }

  }

  struct DragHandle: View {
    let surfaceView: GhosttySurfaceView
    private let handleHeight: CGFloat = 10
    @State private var isHovering = false

    var body: some View {
      Rectangle()
        .fill(Color.primary.opacity(isHovering ? 0.12 : 0))
        .frame(maxWidth: .infinity)
        .frame(height: handleHeight)
        .overlay {
          if isHovering {
            Image(systemName: "ellipsis")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.primary.opacity(0.5))
              .accessibilityHidden(true)
          }
        }
        .contentShape(.rect)
        .onHover { hovering in
          guard hovering != isHovering else { return }
          isHovering = hovering
          if hovering {
            NSCursor.openHand.push()
          } else {
            NSCursor.pop()
          }
        }
        .onDisappear {
          if isHovering {
            isHovering = false
            NSCursor.pop()
          }
        }
        .onDrag {
          TerminalSplitTreeView.dragProvider(for: surfaceView)
        }
    }
  }

  enum DropState: Equatable {
    case idle
    case dropping(DropZone)
  }

  struct SplitDropDelegate: DropDelegate {
    @Binding var dropState: DropState
    let viewSize: CGSize
    let destinationId: UUID
    let action: (Operation) -> Void

    func validateDrop(info: DropInfo) -> Bool {
      info.hasItemsConforming(to: [TerminalSplitTreeView.dragType])
    }

    func dropEntered(info: DropInfo) {
      dropState = .dropping(.calculate(at: info.location, in: viewSize))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
      dropState = .dropping(.calculate(at: info.location, in: viewSize))
      return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
      dropState = .idle
    }

    func performDrop(info: DropInfo) -> Bool {
      let zone = DropZone.calculate(at: info.location, in: viewSize)
      dropState = .idle

      let providers = info.itemProviders(for: [TerminalSplitTreeView.dragType])
      guard let provider = providers.first else { return false }
      provider.loadDataRepresentation(
        forTypeIdentifier: TerminalSplitTreeView.dragType.identifier
      ) { data, _ in
        guard let data,
          let raw = String(data: data, encoding: .utf8),
          let payloadId = UUID(uuidString: raw)
        else { return }
        Task { @MainActor in
          action(.drop(payloadId: payloadId, destinationId: destinationId, zone: zone))
        }
      }
      return true
    }
  }

  enum DropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    static func calculate(at point: CGPoint, in size: CGSize) -> DropZone {
      let relX = point.x / size.width
      let relY = point.y / size.height

      let distToLeft = relX
      let distToRight = 1 - relX
      let distToTop = relY
      let distToBottom = 1 - relY

      let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

      if minDist == distToLeft { return .left }
      if minDist == distToRight { return .right }
      if minDist == distToTop { return .top }
      return .bottom
    }
  }

  struct DropOverlayView: View {
    let zone: DropZone
    let size: CGSize

    var body: some View {
      let overlayColor = Color.accentColor.opacity(0.3)

      switch zone {
      case .top:
        VStack(spacing: 0) {
          Rectangle()
            .fill(overlayColor)
            .frame(height: size.height / 2)
          Spacer()
        }
      case .bottom:
        VStack(spacing: 0) {
          Spacer()
          Rectangle()
            .fill(overlayColor)
            .frame(height: size.height / 2)
        }
      case .left:
        HStack(spacing: 0) {
          Rectangle()
            .fill(overlayColor)
            .frame(width: size.width / 2)
          Spacer()
        }
      case .right:
        HStack(spacing: 0) {
          Spacer()
          Rectangle()
            .fill(overlayColor)
            .frame(width: size.width / 2)
        }
      }
    }
  }
}
