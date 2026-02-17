import AppKit
import SwiftUI

struct TerminalTabView: View {
  let tab: TerminalTabItem
  let isActive: Bool
  let isDragging: Bool
  let tabIndex: Int
  let fixedWidth: CGFloat?
  let onSelect: () -> Void
  let onClose: () -> Void
  @Binding var closeButtonGestureActive: Bool

  @State private var isHovering = false
  @State private var isHoveringClose = false
  @State private var isPressing = false
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    ZStack(alignment: .trailing) {
      Button(action: onSelect) {
        TerminalTabLabelView(
          tab: tab,
          isActive: isActive,
          isHoveringTab: isHovering,
          isHoveringClose: isHoveringClose,
          shortcutHint: shortcutHint,
          showsShortcutHint: showsShortcutHint
        )
      }
      .buttonStyle(TerminalTabButtonStyle(isPressing: $isPressing))
      .frame(
        minWidth: TerminalTabBarMetrics.tabMinWidth,
        maxWidth: TerminalTabBarMetrics.tabMaxWidth,
        minHeight: TerminalTabBarMetrics.tabHeight,
        maxHeight: TerminalTabBarMetrics.tabHeight
      )
      .frame(width: fixedWidth)
      .contentShape(.rect)
      .help("Open tab \(tab.title)")
      .accessibilityLabel(tab.title)

      TerminalTabCloseButton(
        isHoveringTab: isHovering,
        isDragging: isDragging,
        isShowingShortcutHint: showsShortcutHint,
        closeAction: onClose,
        closeButtonGestureActive: $closeButtonGestureActive,
        isHoveringClose: $isHoveringClose
      )
      .padding(.trailing, TerminalTabBarMetrics.tabHorizontalPadding)
    }
    .background {
      TerminalTabBackground(
        isActive: isActive,
        isPressing: isPressing,
        isDragging: isDragging,
        isHovering: isHovering
      )
      .animation(.easeInOut(duration: TerminalTabBarMetrics.hoverAnimationDuration), value: isHovering)
    }
    .padding(.bottom, isActive ? TerminalTabBarMetrics.activeTabBottomPadding : 0)
    .offset(y: isActive ? TerminalTabBarMetrics.activeTabOffset : 0)
    .clipShape(.rect(cornerRadius: TerminalTabBarMetrics.tabCornerRadius))
    .contentShape(.rect)
    .onHover { hovering in
      isHovering = hovering
    }
    .zIndex(isActive ? 2 : (isDragging ? 3 : 0))
    .background(
      TerminalTabMiddleClickOverlay(onMiddleClick: onClose)
    )
  }

  private var shortcutHint: String? {
    let number = tabIndex + 1
    guard number > 0 && number <= 9 else { return nil }
    return "⌘\(number)"
  }

  private var showsShortcutHint: Bool {
    commandKeyObserver.isPressed && shortcutHint != nil
  }
}

private struct TerminalTabMiddleClickOverlay: NSViewRepresentable {
  let onMiddleClick: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onMiddleClick: onMiddleClick)
  }

  func makeNSView(context: Context) -> TerminalTabMiddleClickNSView {
    let view = TerminalTabMiddleClickNSView()
    view.coordinator = context.coordinator
    return view
  }

  func updateNSView(_ nsView: TerminalTabMiddleClickNSView, context: Context) {
    context.coordinator.onMiddleClick = onMiddleClick
    nsView.coordinator = context.coordinator
    nsView.attachGestureRecognizerIfNeeded()
  }

  static func dismantleNSView(_ nsView: TerminalTabMiddleClickNSView, coordinator: Coordinator) {
    nsView.detachGestureRecognizer()
  }

  final class Coordinator: NSObject {
    var onMiddleClick: () -> Void

    init(onMiddleClick: @escaping () -> Void) {
      self.onMiddleClick = onMiddleClick
    }

    @objc func handleMiddleClick(_ recognizer: NSClickGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      onMiddleClick()
    }
  }
}

private final class TerminalTabMiddleClickNSView: NSView {
  weak var coordinator: TerminalTabMiddleClickOverlay.Coordinator?
  private weak var observedView: NSView?
  private var middleClickRecognizer: NSClickGestureRecognizer?

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    attachGestureRecognizerIfNeeded()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    attachGestureRecognizerIfNeeded()
  }

  func attachGestureRecognizerIfNeeded() {
    guard let superview else {
      detachGestureRecognizer()
      return
    }
    if observedView !== superview {
      detachGestureRecognizer()
      observedView = superview
    }
    guard middleClickRecognizer == nil, let coordinator else { return }
    let recognizer = NSClickGestureRecognizer(
      target: coordinator,
      action: #selector(TerminalTabMiddleClickOverlay.Coordinator.handleMiddleClick(_:))
    )
    recognizer.buttonMask = 1 << 2
    recognizer.numberOfClicksRequired = 1
    middleClickRecognizer = recognizer
    superview.addGestureRecognizer(recognizer)
  }

  func detachGestureRecognizer() {
    if let middleClickRecognizer {
      observedView?.removeGestureRecognizer(middleClickRecognizer)
      self.middleClickRecognizer = nil
    }
    observedView = nil
  }

  deinit {
    detachGestureRecognizer()
  }
}
