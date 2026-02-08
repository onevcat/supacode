import SwiftUI

struct TerminalTabBarTrailingAccessories: View {
  let createTab: () -> Void
  let splitHorizontally: () -> Void
  let splitVertically: () -> Void
  let canSplit: Bool

  @Environment(GhosttyShortcutManager.self)
  private var ghosttyShortcuts
  @Environment(CommandKeyObserver.self)
  private var commandKeyObserver

  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var isHoverPopoverPresented = false
  @State private var openTask: Task<Void, Never>?
  @State private var closeTask: Task<Void, Never>?

  var body: some View {
    Button {
      createTab()
      isHoverPopoverPresented = false
    } label: {
      if commandKeyObserver.isPressed {
        HStack(spacing: TerminalTabBarMetrics.contentSpacing) {
          Text("New Tab")
            .font(.caption)
          if let shortcut = ghosttyShortcuts.display(for: "new_tab") {
            ShortcutHintView(text: shortcut, color: TerminalTabBarColors.inactiveText)
          }
        }
      } else {
        Label("New Tab", systemImage: "plus")
          .labelStyle(.iconOnly)
      }
    }
    .buttonStyle(.borderless)
    .help(helpText("New Tab", shortcut: ghosttyShortcuts.display(for: "new_tab")))
    .onHover { hovering in
      isHoveringButton = hovering
      updateHoverPopoverVisibility()
    }
    .popover(
      isPresented: $isHoverPopoverPresented,
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .top
    ) {
      hoverPopoverContent
        .onHover { hovering in
          isHoveringPopover = hovering
          updateHoverPopoverVisibility()
        }
    }
    .frame(height: TerminalTabBarMetrics.barHeight)
    .padding(.trailing, 8)
  }

  private var hoverPopoverContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        createTab()
        isHoverPopoverPresented = false
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus")
          Text("New Tab")
          Spacer(minLength: 0)
          if let shortcut = ghosttyShortcuts.display(for: "new_tab") {
            ShortcutHintView(text: shortcut, color: TerminalTabBarColors.inactiveText)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(helpText("New Tab", shortcut: ghosttyShortcuts.display(for: "new_tab")))

      Divider()

      Button {
        splitVertically()
        isHoverPopoverPresented = false
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "rectangle.righthalf.inset.filled")
          Text("Split Vertically")
          Spacer(minLength: 0)
          if let shortcut = ghosttyShortcuts.display(for: "new_split:right") {
            ShortcutHintView(text: shortcut, color: TerminalTabBarColors.inactiveText)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(helpText("Split Vertically", shortcut: ghosttyShortcuts.display(for: "new_split:right")))
      .disabled(!canSplit)

      Button {
        splitHorizontally()
        isHoverPopoverPresented = false
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "rectangle.bottomhalf.inset.filled")
          Text("Split Horizontally")
          Spacer(minLength: 0)
          if let shortcut = ghosttyShortcuts.display(for: "new_split:down") {
            ShortcutHintView(text: shortcut, color: TerminalTabBarColors.inactiveText)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(helpText("Split Horizontally", shortcut: ghosttyShortcuts.display(for: "new_split:down")))
      .disabled(!canSplit)
    }
    .padding(10)
    .frame(minWidth: 220)
  }

  private func helpText(_ title: String, shortcut: String?) -> String {
    guard let shortcut else { return title }
    return "\(title) (\(shortcut))"
  }

  private func updateHoverPopoverVisibility() {
    if isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      closeTask = nil
      guard !isHoverPopoverPresented else { return }
      openTask?.cancel()
      openTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(250))
        if isHoveringButton || isHoveringPopover {
          isHoverPopoverPresented = true
        }
      }
    } else {
      openTask?.cancel()
      openTask = nil

      // Avoid flicker when moving the cursor from the button into the popover.
      closeTask?.cancel()
      closeTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        if !isHoveringButton && !isHoveringPopover {
          isHoverPopoverPresented = false
        }
      }
    }
  }
}
