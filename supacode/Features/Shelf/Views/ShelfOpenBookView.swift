import AppKit
import SwiftUI

private let shelfLogger = SupaLogger("Shelf")

/// Renders the terminal content for the currently open book.
///
/// Mirrors the terminal-content slice of `WorktreeTerminalTabsView` without
/// the horizontal tab bar: in Shelf the tab bar lives on the book's spine,
/// so we only render the content stack (plus icon picker sheet + focus
/// observer) here. Focus management (`ensureInitialTab`, `focusSelectedTab`,
/// window-key syncing, and the `forceAutoFocus` on-change plumbing) is
/// copied verbatim from `WorktreeTerminalTabsView` so that typing into the
/// open book's surface works the same way it does in normal view.
struct ShelfOpenBookView: View {
  let worktree: Worktree
  let manager: WorktreeTerminalManager
  let shouldRunSetupScript: Bool
  let forceAutoFocus: Bool

  @State private var windowActivity = WindowActivityState.inactive

  var body: some View {
    let state = manager.state(for: worktree) { shouldRunSetupScript }
    Group {
      if let selectedId = state.tabManager.selectedTabId {
        TerminalTabContentStack(tabs: state.tabManager.tabs, selectedTabId: selectedId) { tabId in
          TerminalSplitTreeAXContainer(tree: state.splitTree(for: tabId)) { operation in
            state.performSplitOperation(operation, in: tabId)
          }
        }
      } else {
        EmptyTerminalPaneView(message: "No terminals open")
      }
    }
    .sheet(
      item: Binding(
        get: { state.iconPickerTabId },
        set: { state.iconPickerTabId = $0 }
      )
    ) { tabId in
      let currentIcon = state.tabManager.tabs.first(where: { $0.id == tabId })?.icon
      TabIconPickerView(
        initialIcon: currentIcon,
        defaultIcon: state.defaultIcon(for: tabId),
        onApply: { newIcon in
          state.applyIconChange(tabId, icon: newIcon)
          state.dismissIconPicker()
        },
        onCancel: {
          state.dismissIconPicker()
        }
      )
    }
    .background(
      WindowFocusObserverView { activity in
        windowActivity = activity
        state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
      }
    )
    .onAppear {
      shelfLogger.interval("OpenBook.onAppear") {
        state.ensureInitialTab(focusing: false)
        if shouldAutoFocusTerminal {
          state.focusSelectedTab()
        }
        let activity = resolvedWindowActivity
        state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
      }
    }
    .onDisappear {
      // Long-term diagnostic — pairs with `OpenBook.onAppear` so that
      // any future regression in the per-book-switch teardown/remount
      // cadence shows up as a count delta on the Points of Interest
      // timeline.
      shelfLogger.event("OpenBook.onDisappear")
    }
    .onChange(of: state.tabManager.selectedTabId) { _, _ in
      shelfLogger.interval("OpenBook.onChange.selectedTabId") {
        if shouldAutoFocusTerminal {
          state.focusSelectedTab()
        }
        let activity = resolvedWindowActivity
        state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
      }
    }
  }

  private var shouldAutoFocusTerminal: Bool {
    if forceAutoFocus {
      return true
    }
    guard let responder = NSApp.keyWindow?.firstResponder else { return true }
    return !(responder is NSTableView) && !(responder is NSOutlineView)
  }

  private var resolvedWindowActivity: WindowActivityState {
    if let keyWindow = NSApp.keyWindow {
      return WindowActivityState(
        isKeyWindow: keyWindow.isKeyWindow,
        isVisible: keyWindow.occlusionState.contains(.visible)
      )
    }
    return windowActivity
  }
}
