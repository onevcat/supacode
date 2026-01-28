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
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    .frame(
      minWidth: TerminalTabBarMetrics.tabMinWidth,
      maxWidth: TerminalTabBarMetrics.tabMaxWidth,
      minHeight: TerminalTabBarMetrics.tabHeight,
      maxHeight: TerminalTabBarMetrics.tabHeight
    )
    .frame(width: fixedWidth)
    .padding(.bottom, isActive ? TerminalTabBarMetrics.activeTabBottomPadding : 0)
    .offset(y: isActive ? TerminalTabBarMetrics.activeTabOffset : 0)
    .clipShape(.rect(cornerRadius: TerminalTabBarMetrics.tabCornerRadius))
    .contentShape(.rect)
    .onHover { hovering in
      isHovering = hovering
    }
    .zIndex(isActive ? 2 : (isDragging ? 3 : 0))
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
