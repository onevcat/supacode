import AppKit
import SwiftUI

struct CanvasCardView: View {
  let repositoryName: String
  let worktreeName: String
  /// User-pinned icon for this card's repository, drawn before the
  /// repo name in the title bar. `nil` keeps the historical text-only
  /// title bar.
  var repositoryIcon: RepositoryIconSource?
  /// User-pinned color for this card's repository. When set, it tints
  /// both the icon (if tintable) and the title-bar background as an
  /// always-on identity strip.
  var repositoryColor: Color?
  /// Repo root URL, needed by `RepositoryIconImage` to resolve user
  /// PNG/SVG filenames against the per-repo icons directory.
  var repositoryRootURL: URL?
  let tree: SplitTree<GhosttySurfaceView>
  let isFocused: Bool
  let isSelected: Bool
  let hasUnseenNotification: Bool
  let cardSize: CGSize
  let canvasScale: CGFloat
  let showsSelectionShield: Bool
  let onTap: () -> Void
  let onSelectionTap: () -> Void
  let onDragCommit: (CGSize) -> Void
  let onResize: (CardResizeEdge, CGSize) -> Void
  let onResizeEnd: () -> Void
  let onSplitOperation: (TerminalSplitTreeView.Operation) -> Void
  let onTitleBarTap: () -> Void
  let onExpand: () -> Void
  let onClose: () -> Void

  enum CardResizeEdge {
    case leading, trailing, top, bottom
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// Sign multipliers for width and height during resize.
    /// +1 = trailing/bottom grows, -1 = leading/top grows, 0 = no change.
    var resizeSigns: (width: Int, height: Int) {
      switch self {
      case .leading: (-1, 0)
      case .trailing: (1, 0)
      case .top: (0, -1)
      case .bottom: (0, 1)
      case .topLeading: (-1, -1)
      case .topTrailing: (1, -1)
      case .bottomLeading: (-1, 1)
      case .bottomTrailing: (1, 1)
      }
    }
  }

  private let titleBarHeight: CGFloat = 28
  private let cornerRadius: CGFloat = 8

  // Gesture-driven drag state: does NOT trigger body re-evaluation
  @GestureState private var dragTranslation: CGSize = .zero
  @State private var isHoveringTitleBar: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      terminalContent
    }
    .frame(width: cardSize.width, height: cardSize.height + titleBarHeight)
    .background(cardBackground)
    .clipShape(.rect(cornerRadius: cornerRadius))
    .overlay {
      ZStack {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(borderColor, lineWidth: borderLineWidth)
        if !showsSelectionShield {
          resizeHandles
        }
        if showsSelectionShield {
          selectionShield
        }
      }
    }
    .compositingGroup()
    .contentShape(.rect)
    .accessibilityAddTraits(.isButton)
    .onTapGesture { onTap() }
    .offset(
      x: dragTranslation.width / canvasScale,
      y: dragTranslation.height / canvasScale
    )
  }

  private var borderColor: Color {
    if isFocused {
      .accentColor
    } else if isSelected {
      .accentColor.opacity(0.65)
    } else {
      .secondary.opacity(0.3)
    }
  }

  private var borderLineWidth: CGFloat {
    if isFocused {
      2
    } else if isSelected {
      1.5
    } else {
      1
    }
  }

  @ViewBuilder
  private var cardBackground: some View {
    if isSelected && !isFocused {
      Color.accentColor.opacity(0.08)
    } else {
      Color.clear
    }
  }

  private var titleBar: some View {
    HStack(spacing: 6) {
      if let repositoryIcon, let repositoryRootURL {
        RepositoryIconImage(
          icon: repositoryIcon,
          repositoryRootURL: repositoryRootURL,
          tintColor: repositoryColor,
          size: 12
        )
      }
      Text(repositoryName)
        .font(.caption.bold())
        .lineLimit(1)
      Text("/ \(worktreeName)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
      titleBarActions
    }
    .padding(.horizontal, 8)
    .frame(height: titleBarHeight)
    .frame(maxWidth: .infinity)
    .background(titleBarBackground)
    .accessibilityAddTraits(.isButton)
    .onTapGesture { onTitleBarTap() }
    .onHover { hovering in
      isHoveringTitleBar = hovering
    }
    .gesture(
      DragGesture(coordinateSpace: .global)
        .updating($dragTranslation) { value, state, _ in
          state = value.translation
        }
        .onEnded { value in
          onDragCommit(
            CGSize(
              width: value.translation.width / canvasScale,
              height: value.translation.height / canvasScale
            ))
        }
    )
  }

  private var titleBarActions: some View {
    HStack(spacing: 2) {
      Button {
        onExpand()
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.caption2.weight(.semibold))
          .frame(width: 18, height: 18)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Expand to tab view")
      .accessibilityLabel("Expand card")

      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.caption2.weight(.semibold))
          .frame(width: 18, height: 18)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Close card")
      .accessibilityLabel("Close card")
    }
    .opacity(isHoveringTitleBar ? 1 : 0)
    .allowsHitTesting(isHoveringTitleBar)
    .animation(.easeInOut(duration: 0.15), value: isHoveringTitleBar)
  }

  @ViewBuilder
  private var titleBarBackground: some View {
    // Layering: existing notification orange + selected accent stay
    // BELOW the `.bar` material so their behavior is unchanged from
    // before this feature shipped. The repo color sits ABOVE the bar
    // as a thin always-on identity strip — putting it below would
    // dilute it to invisibility against the 0.9-opaque material, and
    // moving the bar to the bottom would amplify the existing tints.
    ZStack {
      if hasUnseenNotification {
        Color.orange.opacity(0.3)
      }
      if isSelected && !isFocused {
        Color.accentColor.opacity(0.12)
      }
      Rectangle()
        .fill(.bar)
        .opacity(0.9)
      if let repositoryColor {
        repositoryColor.opacity(isFocused ? 0.18 : 0.10)
      }
    }
  }

  private var terminalContent: some View {
    TerminalSplitTreeView(tree: tree, pinnedSize: cardSize, action: onSplitOperation)
      .frame(width: cardSize.width, height: cardSize.height)
      .allowsHitTesting(isFocused && !showsSelectionShield)
  }

  private var selectionShield: some View {
    Color.clear
      .contentShape(.rect)
      .accessibilityAddTraits(.isButton)
      .onTapGesture { onSelectionTap() }
  }

  // MARK: - Resize Handles

  private let edgeThickness: CGFloat = 10
  private let cornerSide: CGFloat = 18

  private var resizeHandles: some View {
    ZStack {
      edgeHandle(
        cursor: .frameResize(position: .left, directions: .all),
        isVertical: true,
        edgeOffset: CGSize(width: -edgeThickness / 2, height: 0)
      ) { translation in
        onResize(.leading, translation)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

      edgeHandle(
        cursor: .frameResize(position: .right, directions: .all),
        isVertical: true,
        edgeOffset: CGSize(width: edgeThickness / 2, height: 0)
      ) { translation in
        onResize(.trailing, translation)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

      edgeHandle(
        cursor: .frameResize(position: .top, directions: .all),
        isVertical: false,
        edgeOffset: CGSize(width: 0, height: -edgeThickness / 2)
      ) { translation in
        onResize(.top, translation)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      edgeHandle(
        cursor: .frameResize(position: .bottom, directions: .all),
        isVertical: false,
        edgeOffset: CGSize(width: 0, height: edgeThickness / 2)
      ) { translation in
        onResize(.bottom, translation)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      cornerHandle(
        cursor: .frameResize(position: .topLeft, directions: .all),
        alignment: .topLeading
      ) { translation in
        onResize(.topLeading, translation)
      }

      cornerHandle(
        cursor: .frameResize(position: .topRight, directions: .all),
        alignment: .topTrailing
      ) { translation in
        onResize(.topTrailing, translation)
      }

      cornerHandle(
        cursor: .frameResize(position: .bottomLeft, directions: .all),
        alignment: .bottomLeading
      ) { translation in
        onResize(.bottomLeading, translation)
      }

      cornerHandle(
        cursor: .frameResize(position: .bottomRight, directions: .all),
        alignment: .bottomTrailing
      ) { translation in
        onResize(.bottomTrailing, translation)
      }
    }
  }

  private func edgeHandle(
    cursor: NSCursor,
    isVertical: Bool,
    edgeOffset: CGSize,
    onChange: @escaping (CGSize) -> Void
  ) -> some View {
    ResizeCursorView(cursor: cursor) {
      Color.clear
        .frame(
          width: isVertical ? edgeThickness : nil,
          height: isVertical ? nil : edgeThickness
        )
        .frame(
          maxWidth: isVertical ? nil : .infinity,
          maxHeight: isVertical ? .infinity : nil
        )
        .contentShape(.rect)
        .gesture(
          DragGesture(coordinateSpace: .global)
            .onChanged { value in onChange(value.translation) }
            .onEnded { _ in onResizeEnd() }
        )
    }
    .offset(edgeOffset)
  }

  private func cornerHandle(
    cursor: NSCursor,
    alignment: Alignment,
    onChange: @escaping (CGSize) -> Void
  ) -> some View {
    ResizeCursorView(cursor: cursor) {
      Color.clear
        .frame(width: cornerSide, height: cornerSide)
        .contentShape(.rect)
        .gesture(
          DragGesture(coordinateSpace: .global)
            .onChanged { value in onChange(value.translation) }
            .onEnded { _ in onResizeEnd() }
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    .offset(
      x: (alignment == .bottomTrailing || alignment == .topTrailing) ? cornerSide / 3 : -cornerSide / 3,
      y: (alignment == .topLeading || alignment == .topTrailing) ? -cornerSide / 3 : cornerSide / 3
    )
  }
}

private struct ResizeCursorView<Content: View>: View {
  let cursor: NSCursor
  @ViewBuilder let content: Content
  @State private var isHovered = false

  var body: some View {
    content
      .onHover { hovering in
        guard hovering != isHovered else { return }
        isHovered = hovering
        if hovering {
          cursor.push()
        } else {
          NSCursor.pop()
        }
      }
  }
}
