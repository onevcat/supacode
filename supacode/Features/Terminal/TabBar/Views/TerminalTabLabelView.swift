import SwiftUI

struct TerminalTabLabelView: View {
  let tab: TerminalTabItem
  let isActive: Bool
  let isHoveringTab: Bool
  let isDragging: Bool
  let tabIndex: Int
  let closeAction: () -> Void
  @Binding var closeButtonGestureActive: Bool
  @Binding var isHoveringClose: Bool
  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    HStack(spacing: TerminalTabBarMetrics.contentSpacing) {
      if let icon = tab.icon {
        Image(systemName: icon)
          .imageScale(.small)
          .foregroundStyle(isActive ? TerminalTabBarColors.activeText : TerminalTabBarColors.inactiveText)
          .accessibilityHidden(true)
      }
      Text(tab.title)
        .font(.caption)
        .monospaced()
        .lineLimit(1)
        .foregroundStyle(isActive ? TerminalTabBarColors.activeText : TerminalTabBarColors.inactiveText)
      Spacer(minLength: TerminalTabBarMetrics.contentTrailingSpacing)
      ZStack {
        if commandKeyObserver.isPressed, let shortcutHint {
          ShortcutHintView(text: shortcutHint, color: TerminalTabBarColors.inactiveText)
        } else {
          if tab.isDirty && !isHoveringTab && !isHoveringClose {
            Circle()
              .fill(TerminalTabBarColors.dirtyIndicator)
              .frame(
                width: TerminalTabBarMetrics.dirtyIndicatorSize,
                height: TerminalTabBarMetrics.dirtyIndicatorSize
              )
          }
          TerminalTabCloseButton(
            isHoveringTab: isHoveringTab,
            isDragging: isDragging,
            closeAction: closeAction,
            closeButtonGestureActive: $closeButtonGestureActive,
            isHoveringClose: $isHoveringClose
          )
        }
      }
    }
    .frame(maxHeight: .infinity)
    .padding(.horizontal, TerminalTabBarMetrics.tabHorizontalPadding)
  }

  private var shortcutHint: String? {
    let number = tabIndex + 1
    guard number > 0 && number <= 9 else { return nil }
    return "⌘\(number)"
  }
}
