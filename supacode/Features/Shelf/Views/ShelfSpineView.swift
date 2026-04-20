import SwiftUI

/// Vertical spine rendering for a single book on the Shelf.
///
/// Phase 3 scope: header with book-level notification dot, a vertical
/// scrollable tab list (icon-only slots), tap targets for header (opens
/// the book with its current tab) and per-tab slot (opens the book with
/// that tab). Animations, ⌘-held digit overlay, and bottom controls are
/// layered in subsequent phases.
struct ShelfSpineView: View {
  let book: ShelfBook
  let isOpen: Bool
  let terminalState: WorktreeTerminalState?
  let onOpenBook: () -> Void
  let onSelectTab: (TerminalTabID) -> Void
  /// Bottom controls — provided only for the open book's spine. `nil`
  /// suppresses the trio entirely.
  let onNewTab: (() -> Void)?
  let onSplitVertical: (() -> Void)?
  let onSplitHorizontal: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      headerButton
      tabList
      // Flexible spacer keeps the tap target for "open this book" filling
      // any leftover vertical space between the tab list and the bottom
      // controls.
      Button(action: onOpenBook) {
        Color.clear
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      bottomControls
    }
    .frame(width: ShelfMetrics.spineWidth)
    .background(spineBackground)
    .overlay(alignment: .trailing) {
      if !isOpen {
        Divider().opacity(0.35)
      }
    }
    .help(book.displayName)
  }

  @ViewBuilder
  private var bottomControls: some View {
    if let onNewTab, let onSplitVertical, let onSplitHorizontal {
      VStack(spacing: ShelfMetrics.slotSpacing) {
        Divider().opacity(0.3)
        ShelfSpineControlButton(
          systemImage: "plus",
          label: "New Tab",
          action: onNewTab
        )
        ShelfSpineControlButton(
          systemImage: "square.split.2x1",
          label: "Split Vertically",
          action: onSplitVertical
        )
        ShelfSpineControlButton(
          systemImage: "square.split.1x2",
          label: "Split Horizontally",
          action: onSplitHorizontal
        )
      }
      .padding(.horizontal, ShelfMetrics.slotHorizontalPadding)
      .padding(.bottom, ShelfMetrics.slotSpacing)
    }
  }

  @ViewBuilder
  private var headerButton: some View {
    Button(action: onOpenBook) {
      ShelfSpineHeader(
        book: book,
        hasAggregatedNotification: terminalState?.hasUnseenNotification == true
      )
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var tabList: some View {
    if let terminalState {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: ShelfMetrics.slotSpacing) {
          ForEach(Array(terminalState.tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
            // 1-based hotkey number that matches Cmd+1..9. Tabs at
            // positions 10+ intentionally have no hotkey: they keep
            // showing their icon even while ⌘ is held.
            let hotkeyIndex = index < 9 ? index + 1 : nil
            ShelfSpineTabSlot(
              tab: tab,
              hotkeyIndex: hotkeyIndex,
              isActive: terminalState.tabManager.selectedTabId == tab.id,
              hasUnseenNotification: terminalState.hasUnseenNotification(for: tab.id),
              onTap: { onSelectTab(tab.id) }
            )
          }
        }
        .padding(.horizontal, ShelfMetrics.slotHorizontalPadding)
        .padding(.top, ShelfMetrics.slotSpacing)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  @ViewBuilder
  private var spineBackground: some View {
    if isOpen {
      Color.accentColor.opacity(0.12)
    } else {
      Color.clear
    }
  }
}

private struct ShelfSpineHeader: View {
  let book: ShelfBook
  let hasAggregatedNotification: Bool

  var body: some View {
    VStack(spacing: 6) {
      ZStack(alignment: .top) {
        Circle()
          .fill(.orange)
          .frame(width: ShelfMetrics.aggregatedDotSize, height: ShelfMetrics.aggregatedDotSize)
          .opacity(hasAggregatedNotification ? 1 : 0)
          .accessibilityLabel("Unread notifications")
          .accessibilityHidden(!hasAggregatedNotification)
      }
      .frame(height: ShelfMetrics.aggregatedDotSize)
      .padding(.top, 6)
      VStack(spacing: 6) {
        Text(book.displayName)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .fixedSize()
          .rotationEffect(.degrees(90))
          .frame(width: ShelfMetrics.spineWidth, alignment: .center)
        if let branchName = book.branchName, branchName != book.displayName {
          Text(branchName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize()
            .rotationEffect(.degrees(90))
            .frame(width: ShelfMetrics.spineWidth, alignment: .center)
        }
      }
      .padding(.top, 30)
      .padding(.bottom, 10)
    }
  }
}

private struct ShelfSpineTabSlot: View {
  let tab: TerminalTabItem
  let hotkeyIndex: Int?
  let isActive: Bool
  let hasUnseenNotification: Bool
  let onTap: () -> Void

  @Environment(CommandKeyObserver.self) private var commandKeyObserver

  var body: some View {
    Button(action: onTap) {
      ZStack {
        backgroundFill
        slotContent
      }
      .frame(width: ShelfMetrics.slotSize, height: ShelfMetrics.slotSize)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help(tab.title)
  }

  /// When ⌘ is held AND this tab has a `Cmd+N` hotkey, swap the icon
  /// for the digit in-place. Slot frame stays the same either way so
  /// nothing reflows.
  @ViewBuilder
  private var slotContent: some View {
    let showsHotkey = commandKeyObserver.isPressed && hotkeyIndex != nil
    if let hotkeyIndex, showsHotkey {
      Text("\(hotkeyIndex)")
        .font(.callout.weight(.semibold).monospacedDigit())
        .foregroundStyle(foregroundTint)
        .accessibilityHidden(true)
    } else {
      Image(systemName: tab.icon ?? ShelfMetrics.defaultTabIcon)
        .imageScale(.small)
        .foregroundStyle(foregroundTint)
        // Dim tabs without a hotkey when ⌘ is held, so the "this slot
        // can't be jumped to via Cmd+N" affordance is legible without
        // shifting any layout.
        .opacity(commandKeyObserver.isPressed && hotkeyIndex == nil ? 0.45 : 1)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var backgroundFill: some View {
    if hasUnseenNotification {
      // Same tint as Canvas title-bar notification highlight so Shelf's
      // per-tab unread indicator reads as "this tab" rather than a new
      // idiom. Wins over the active-tab highlight when both apply.
      RoundedRectangle(cornerRadius: ShelfMetrics.slotCornerRadius, style: .continuous)
        .fill(Color.orange.opacity(0.3))
    } else if isActive {
      RoundedRectangle(cornerRadius: ShelfMetrics.slotCornerRadius, style: .continuous)
        .fill(Color.accentColor.opacity(0.2))
    } else {
      Color.clear
    }
  }

  private var foregroundTint: Color {
    if hasUnseenNotification { return .primary }
    if isActive { return .primary }
    return .secondary
  }
}

private struct ShelfSpineControlButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .imageScale(.small)
        .foregroundStyle(.secondary)
        .frame(width: ShelfMetrics.slotSize, height: ShelfMetrics.slotSize)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .help(label)
  }
}

/// Shared metrics for the Shelf layout so the three segments stay in sync.
enum ShelfMetrics {
  /// Width of a single spine (roughly one line of text).
  static let spineWidth: CGFloat = 26
  static let slotSize: CGFloat = 22
  static let slotCornerRadius: CGFloat = 4
  static let slotSpacing: CGFloat = 3
  static let slotHorizontalPadding: CGFloat = 2
  static let aggregatedDotSize: CGFloat = 6
  /// Fallback icon when a tab has no custom icon set.
  static let defaultTabIcon: String = "terminal"
}
