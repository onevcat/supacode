import Sharing
import SwiftUI

private let shelfLogger = SupaLogger("Shelf")

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
  /// Absolute distance along the ordered book list between this spine and
  /// the currently open book (0 = this *is* the open book, 1 = immediate
  /// neighbor, …). Nil when no book is open. Drives the step-wise accent
  /// tint that fades outward from the open book, so proximity reads at a
  /// glance instead of every non-open spine looking identical.
  let distanceFromOpen: Int?
  let terminalState: WorktreeTerminalState?
  let onOpenBook: () -> Void
  let onSelectTab: (TerminalTabID) -> Void
  /// Bottom controls — provided only for the open book's spine. `nil`
  /// suppresses the trio entirely.
  let onNewTab: (() -> Void)?
  let onSplitVertical: (() -> Void)?
  let onSplitHorizontal: (() -> Void)?
  /// "Close this book" — drives the book-level context menu entry on
  /// the spine header / empty body. Nil disables the menu. The label
  /// text is supplied by the parent so it can vary per book kind
  /// ("Close Worktree" vs "Close Folder") without leaking the `Kind`
  /// enum into this view.
  let closeMenuTitle: String
  let onCloseBook: (() -> Void)?
  /// "Repo Settings" — opens the per-repo Settings tab. Always
  /// available regardless of book kind since every book belongs to a
  /// repository.
  let onOpenRepositorySettings: () -> Void

  @State private var isHovering = false
  @Shared(.repositoryAppearances) private var repositoryAppearances
  @Environment(GhosttyShortcutManager.self) private var ghosttyShortcuts

  var body: some View {
    // Body-invocation counter signpost. With ~10 spines visible during
    // a book switch, the trace can multiply this event count by spine
    // count to estimate per-click body work. Emitted as a no-arg event
    // (instant timeline marker) so it imposes no work even when
    // Instruments isn't attached.
    let _ = shelfLogger.event("ShelfSpineView.body")
    VStack(spacing: 0) {
      headerButton
      tabList
      bottomControls
    }
    .frame(width: ShelfMetrics.spineWidth)
    // `maxHeight: .infinity` binds the spine to the parent Shelf's
    // available height (set by `ShelfView.frame(maxHeight: .infinity)`).
    // Without this, a long tab list would let the spine VStack grow to
    // its intrinsic size and push the entire window taller.
    .frame(maxHeight: .infinity, alignment: .top)
    .background(
      // Single `Rectangle` with a computed fill so the color change
      // interpolates in place as `distanceFromOpen` shifts, rather than
      // swapping one view for another (which the previous `@ViewBuilder`
      // if/else did). Fill is derived from a stepped accent-alpha ladder
      // so the open book glows strongest and neighbors fade outward.
      Rectangle().fill(spineBackgroundColor)
    )
    // Whole-spine tap target. Inner Buttons (header, tab slots, controls)
    // absorb their own clicks; clicks that fall on empty areas (scroll
    // view negative space, gaps between tabs, etc.) bubble here and open
    // the book. Keeps the "books on a shelf" metaphor: grab anywhere on
    // the spine to pull the book out.
    .contentShape(.rect)
    .onTapGesture { onOpenBook() }
    .accessibilityAddTraits(.isButton)
    .contextMenu { bookContextMenu }
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .overlay(alignment: .trailing) {
      if !isOpen {
        // Explicit 1pt vertical rule. `Divider()` used here before
        // rendered a *horizontal* hairline (no stack context → default
        // horizontal orientation) spanning the spine's full width at
        // its vertical center, lining up across every closed spine and
        // looking like a single white bar cutting through the Shelf.
        Rectangle()
          .fill(Color.secondary.opacity(0.1))
          .frame(width: 1)
      }
    }
  }

  /// Step-wise accent-alpha ladder keyed by `distanceFromOpen`. 100%
  /// (selected) → 50% → 30% → 20% → 10% → 5%; beyond the ladder the
  /// multiplier is 0 so the halo is bounded. The sharp drop at distance
  /// 1 keeps the open book clearly dominant rather than blending into
  /// its neighbors. Shared by the spine background and the per-tab
  /// active-highlight fill so they fade in lockstep.
  private var accentProximityMultiplier: Double {
    guard let distance = distanceFromOpen else { return 0 }
    let ladder: [Double] = [1.0, 0.5, 0.3, 0.2, 0.1, 0.05]
    return distance < ladder.count ? ladder[distance] : 0
  }

  /// When no book is open (empty shelf), fall back to the neutral gray
  /// used everywhere else so spines don't become invisible; otherwise
  /// derive from the proximity ladder. Hovering an unselected spine
  /// bumps its tint to 80% of the selected book's intensity — a clear
  /// "this is interactable" affordance that sits just below the open
  /// book and animates in/out smoothly.
  ///
  /// When the book's repository has a user-pinned color, that color
  /// replaces `Color.accentColor` as the proximity-tint base so the
  /// shelf reads as "books on shelves" instead of one continuous
  /// accent ribbon. The proximity ladder is unchanged — we only swap
  /// the hue.
  private var spineBackgroundColor: Color {
    guard distanceFromOpen != nil else {
      return Color.primary.opacity(0.06)
    }
    let multiplier = isHovering && !isOpen ? 0.8 : accentProximityMultiplier
    return effectiveTintColor.opacity(0.20 * multiplier)
  }

  /// Repo's pinned color, or `.accentColor` when none — used as the
  /// proximity-tint base and as the icon tint in the header.
  private var effectiveTintColor: Color {
    appearance.color?.color ?? .accentColor
  }

  private var appearance: RepositoryAppearance {
    repositoryAppearances[book.repositoryID] ?? .empty
  }

  /// Active-tab highlight fades more gently than the spine background —
  /// the tab-selection indicator has to stay legible even on far-away
  /// books so users can still see which tab would open. Uses absolute
  /// alpha stops (0.20 / 0.15 / 0.10) rather than the spine's multiplier
  /// ladder; the two axes are tuned independently for their own roles.
  private var activeTabHighlightAlpha: Double {
    guard let distance = distanceFromOpen else { return 0.2 }
    switch distance {
    case 0: return 0.2
    case 1: return 0.15
    default: return 0.1
    }
  }

  @ViewBuilder
  private var bookContextMenu: some View {
    Button {
      onOpenRepositorySettings()
    } label: {
      Text("Repo Settings")
    }
    if let onCloseBook {
      Divider()
      Button {
        onCloseBook()
      } label: {
        Text(closeMenuTitle)
      }
    }
  }

  @ViewBuilder
  private var bottomControls: some View {
    // `+` is shown on every spine, not just the open one: clicking it on a
    // closed book opens that book and creates a tab in one motion (the
    // caller sequences `selectWorktree` → `newTerminal`). Splits only
    // make sense against a focused surface, so they stay scoped to the
    // open book.
    if onNewTab != nil || onSplitVertical != nil || onSplitHorizontal != nil {
      VStack(spacing: ShelfMetrics.slotSpacing) {
        Divider().opacity(0.3)
        if let onNewTab {
          ShelfSpineControlButton(
            systemImage: "plus",
            label: "New Tab",
            shortcut: ghosttyShortcuts.display(for: "new_tab"),
            action: onNewTab
          )
        }
        if let onSplitVertical {
          ShelfSpineControlButton(
            systemImage: "square.split.2x1",
            label: "Split Vertically",
            shortcut: ghosttyShortcuts.display(for: "new_split:right"),
            action: onSplitVertical
          )
        }
        if let onSplitHorizontal {
          ShelfSpineControlButton(
            systemImage: "square.split.1x2",
            label: "Split Horizontally",
            shortcut: ghosttyShortcuts.display(for: "new_split:down"),
            action: onSplitHorizontal
          )
        }
      }
      .padding(.horizontal, ShelfMetrics.slotHorizontalPadding)
      .padding(.top, ShelfMetrics.sectionGap)
      .padding(.bottom, ShelfMetrics.slotSpacing)
    }
  }

  @ViewBuilder
  private var headerButton: some View {
    Button(action: onOpenBook) {
      ShelfSpineHeader(
        book: book,
        hasAggregatedNotification: terminalState?.hasUnseenNotification == true,
        icon: appearance.icon,
        iconTint: effectiveTintColor,
        repositoryRootURL: URL(fileURLWithPath: book.repositoryID)
      )
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .contextMenu { bookContextMenu }
    .help(book.displayName)
  }

  @ViewBuilder
  private var tabList: some View {
    if let terminalState {
      // Scroll the tab slots when they overflow the spine so the window
      // height stays capped instead of growing unbounded with tab count.
      // `.scrollIndicators(.never)` — stronger than `.hidden`, which
      // still shows scroll bars when the user has "Always show scroll
      // bars" enabled in System Settings. The 34pt-wide spine has no
      // room to donate to a scroll bar, so we always hide it.
      // `.scrollBounceBehavior(.basedOnSize)` keeps short lists static.
      // `.clipped()` eats any overdraw at the scroll-view edges so the
      // spine boundary stays crisp.
      ScrollView(.vertical) {
        tabListContent(state: terminalState)
      }
      .scrollIndicators(.never)
      .scrollBounceBehavior(.basedOnSize)
      .clipped()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  @ViewBuilder
  private func tabListContent(state terminalState: WorktreeTerminalState) -> some View {
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
          activeHighlightTint: effectiveTintColor,
          activeHighlightAlpha: activeTabHighlightAlpha,
          onTap: { onSelectTab(tab.id) },
          onClose: { terminalState.closeTab(tab.id) }
        )
        .terminalTabContextMenu(
          tabId: tab.id,
          tabs: terminalState.tabManager.tabs,
          actions: TerminalTabContextMenuActions(
            changeTitle: { terminalState.promptChangeTabTitle($0) },
            changeIcon: { terminalState.presentIconPicker(for: $0) },
            closeTab: { terminalState.closeTab($0) },
            closeOthers: { terminalState.closeOtherTabs(keeping: $0) },
            closeToRight: { terminalState.closeTabsToRight(of: $0) },
            closeAll: { terminalState.closeAllTabs() }
          )
        )
      }
    }
    .padding(.horizontal, ShelfMetrics.slotHorizontalPadding)
    .padding(.top, ShelfMetrics.sectionGap)
  }

}

private struct ShelfSpineHeader: View {
  let book: ShelfBook
  let hasAggregatedNotification: Bool
  let icon: RepositoryIconSource?
  let iconTint: Color
  let repositoryRootURL: URL

  /// Reserved slot for the top decoration (icon and/or notification),
  /// sized at the maximum expected configuration (14pt icon plus a
  /// 6pt badge nudged 3pt outward at the top-trailing corner).
  /// Holding the slot at a constant size — whether or not an icon is
  /// set — keeps every spine's header at the same total height so the
  /// rotated titles align horizontally across the shelf row. When the
  /// repo has no icon AND no notification, the slot is just empty
  /// reserved space.
  private let slotSize: CGFloat = 18
  private let iconSize: CGFloat = 14
  private let badgeSize: CGFloat = 6
  private let badgeOffset: CGFloat = 3

  var body: some View {
    VStack(spacing: 8) {
      slot
      rotatedTitle
    }
    .padding(.top, 8)
  }

  /// Three rendering paths driven by the (icon, notification) matrix:
  /// - icon set: render the icon, hang the notification on it as a
  ///   small badge in the top-trailing corner (macOS app-icon style).
  /// - no icon, has notification: fall back to the original
  ///   standalone orange dot, centered in the slot.
  /// - no icon, no notification: slot stays empty but reserved.
  @ViewBuilder
  private var slot: some View {
    ZStack {
      Color.clear
        .frame(width: slotSize, height: slotSize)

      if let icon {
        RepositoryIconImage(
          icon: icon,
          repositoryRootURL: repositoryRootURL,
          tintColor: iconTint,
          size: iconSize
        )
        .overlay(alignment: .topTrailing) {
          if hasAggregatedNotification {
            notificationBadge
          }
        }
      } else if hasAggregatedNotification {
        Circle()
          .fill(.orange)
          .frame(
            width: ShelfMetrics.aggregatedDotSize,
            height: ShelfMetrics.aggregatedDotSize
          )
      }
    }
    .accessibilityElement()
    .accessibilityLabel(hasAggregatedNotification ? "Unread notifications" : "")
    .accessibilityHidden(!hasAggregatedNotification)
  }

  /// Notification dot rendered as a corner badge over the icon. The
  /// thin dark stroke keeps the orange visible on light spine
  /// backgrounds; without it the badge would disappear on
  /// orange-tinted repos.
  @ViewBuilder
  private var notificationBadge: some View {
    Circle()
      .fill(.orange)
      .frame(width: badgeSize, height: badgeSize)
      .overlay {
        Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5)
      }
      .offset(x: badgeOffset, y: -badgeOffset)
  }

  /// Composed title rendered vertically (top-to-bottom reading direction).
  /// Project name is primary; the `· branch` suffix is secondary so the
  /// user can scan the spine and pick out the repo at a glance even on
  /// repositories with many worktrees.
  @ViewBuilder
  private var rotatedTitle: some View {
    combinedTitle
      .font(.callout)
      .lineLimit(1)
      .truncationMode(.middle)
      .frame(width: ShelfMetrics.headerMaxLength, alignment: .leading)
      .rotationEffect(.degrees(90))
      .frame(width: ShelfMetrics.spineWidth, height: ShelfMetrics.headerMaxLength)
  }

  /// Single composed `Text` (string-interpolation form) so middle-
  /// truncation can operate across project + branch as one string.
  /// `foregroundStyle` on each interpolated piece survives composition
  /// and drives the primary/secondary split.
  private var combinedTitle: Text {
    let project = Text(book.projectName)
      .font(.callout.weight(.semibold))
      .foregroundStyle(.primary)
    guard let branch = book.branchName, !branch.isEmpty else {
      return project
    }
    let branchText = Text(" · \(branch)").foregroundStyle(.secondary)
    return Text("\(project)\(branchText)")
  }
}

private struct ShelfSpineTabSlot: View {
  let tab: TerminalTabItem
  let hotkeyIndex: Int?
  let isActive: Bool
  let hasUnseenNotification: Bool
  /// Hue used for the active-tab background fill — repo color when
  /// the owning book has one pinned, otherwise `Color.accentColor`.
  /// Threaded from the spine so the active-tab indicator stays in
  /// the same color family as the surrounding spine background
  /// instead of clashing with a contrasting accent.
  let activeHighlightTint: Color
  /// Absolute alpha for the active-tab accent fill, supplied by the
  /// enclosing spine so it can fade with proximity on its own curve
  /// (which decays more gently than the spine background — selection
  /// indicators must stay legible even on far books). Orange
  /// notification tint is left untouched so unread signals remain
  /// attention-grabbing regardless of distance.
  let activeHighlightAlpha: Double
  let onTap: () -> Void
  let onClose: () -> Void

  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @State private var isHovering = false

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
    .overlay(alignment: .topTrailing) {
      if isHovering && !commandKeyObserver.isPressed {
        Button(action: onClose) {
          Image(systemName: "xmark.circle.fill")
            .imageScale(.small)
            .foregroundStyle(.primary)
            .background(Circle().fill(.background))
            .accessibilityLabel("Close Tab")
        }
        .buttonStyle(.plain)
        .offset(x: 3, y: -3)
        .help("Close Tab")
      }
    }
    .onHover { hovering in
      isHovering = hovering
    }
    .help(tab.title)
  }

  /// When ⌘ is held AND this tab has a `Cmd+N` hotkey, swap the icon
  /// for a compact `⌘N` glyph in-place. Slot frame stays the same either
  /// way so nothing reflows.
  @ViewBuilder
  private var slotContent: some View {
    let showsHotkey = commandKeyObserver.isPressed && hotkeyIndex != nil
    if let hotkeyIndex, showsHotkey {
      HStack(spacing: 1) {
        Image(systemName: "command")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(foregroundTint)
        Text("\(hotkeyIndex)")
          .font(.callout.weight(.semibold).monospacedDigit())
          .foregroundStyle(foregroundTint)
      }
      .accessibilityHidden(true)
    } else {
      TabIconImage(
        rawName: tab.icon ?? ShelfMetrics.defaultTabIcon,
        pointSize: ShelfMetrics.tabIconPointSize
      )
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
        .fill(activeHighlightTint.opacity(activeHighlightAlpha))
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
  let shortcut: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .imageScale(.medium)
        .foregroundStyle(.secondary)
        .frame(width: ShelfMetrics.slotSize, height: ShelfMetrics.slotSize)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .help(helpText)
  }

  private var helpText: String {
    guard let shortcut else { return label }
    return "\(label) (\(shortcut))"
  }
}

/// Shared metrics for the Shelf layout so the three segments stay in sync.
enum ShelfMetrics {
  /// Width of a single spine. Sized for comfortable one-line-of-text plus
  /// a bit of breathing room around the rotated title.
  static let spineWidth: CGFloat = 34
  static let slotSize: CGFloat = 28
  static let slotCornerRadius: CGFloat = 5
  static let slotSpacing: CGFloat = 3
  static let slotHorizontalPadding: CGFloat = 3
  /// Vertical gap between major spine sections (header → tab list,
  /// tab list → bottom controls). Larger than `slotSpacing` so the
  /// rotated title doesn't crowd into the first tab and the last tab
  /// doesn't crowd into the divider above the `+` button.
  static let sectionGap: CGFloat = 10
  static let aggregatedDotSize: CGFloat = 6
  /// Max pre-rotation width (i.e. visual height after 90° rotation) of the
  /// spine header title. Texts longer than this get middle-truncated.
  static let headerMaxLength: CGFloat = 160
  /// Fallback icon when a tab has no custom icon set.
  static let defaultTabIcon: String = "terminal"
  /// Point size used by `TabIconImage` for both the SF Symbol
  /// (`.font(.system(size:))`) and the asset (`.frame`) branches so
  /// branded artwork visually matches the SF-Symbol fallback.
  static let tabIconPointSize: CGFloat = 18
}
