import SwiftUI

struct TerminalTabLabelView: View {
  let tab: TerminalTabItem
  let isActive: Bool
  let isHoveringTab: Bool
  let isHoveringClose: Bool
  let shortcutHint: String?
  let showsShortcutHint: Bool

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
        .lineLimit(1)
        .foregroundStyle(isActive ? TerminalTabBarColors.activeText : TerminalTabBarColors.inactiveText)
      Spacer(minLength: TerminalTabBarMetrics.contentTrailingSpacing)
      ZStack {
        if showsShortcutHint, let shortcutHint {
          ShortcutHintView(text: shortcutHint, color: TerminalTabBarColors.inactiveText)
        } else if tab.isDirty && !isHoveringTab && !isHoveringClose {
          Circle()
            .fill(TerminalTabBarColors.dirtyIndicator)
            .frame(
              width: TerminalTabBarMetrics.dirtyIndicatorSize,
              height: TerminalTabBarMetrics.dirtyIndicatorSize
            )
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.horizontal, TerminalTabBarMetrics.tabHorizontalPadding)
    .padding(.trailing, TerminalTabBarMetrics.closeButtonSize + TerminalTabBarMetrics.contentSpacing)
  }
}
