import ComposableArchitecture
import SwiftUI

struct CommandPaletteOverlayView: View {
  @Bindable var store: StoreOf<CommandPaletteFeature>
  let items: [CommandPaletteItem]
  @FocusState private var isQueryFocused: Bool
  @State private var hoveredID: CommandPaletteItem.ID?

  var body: some View {
    let filteredItems = CommandPaletteFeature.filterItems(items: items, query: store.query)
    ZStack {
      if store.isPresented {
        ZStack {
          Color.clear
            .contentShape(.rect)
            .onTapGesture {
              store.send(.setPresented(false))
            }

          GeometryReader { geometry in
            VStack {
              Spacer().frame(height: geometry.size.height * 0.05)

              CommandPaletteCard(
                query: $store.query,
                selectedIndex: $store.selectedIndex,
                items: filteredItems,
                hoveredID: $hoveredID,
                isQueryFocused: _isQueryFocused,
                onEvent: { event in
                  switch event {
                  case .exit:
                    store.send(.setPresented(false))
                  case .submit:
                    submitSelected(rows: filteredItems)
                  case .move(let direction):
                    moveSelection(direction, rows: filteredItems)
                  }
                },
                activateShortcut: { index in
                  activateShortcut(index, rows: filteredItems)
                },
                activate: { id in
                  activate(id, rows: filteredItems)
                }
              )
              .zIndex(1)
              .task {
                isQueryFocused = store.isPresented
              }

              Spacer()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
          }
        }
        .ignoresSafeArea()
      }
    }
    .onChange(of: store.isPresented) { _, newValue in
      isQueryFocused = newValue
      if !newValue {
        hoveredID = nil
      }
    }
    .onChange(of: filteredItems) { _, newValue in
      updateSelection(rows: newValue)
    }
  }

  private func updateSelection(rows: [CommandPaletteItem]) {
    let trimmed = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      if store.selectedIndex != nil {
        store.selectedIndex = nil
      }
      return
    }
    let count = rows.count
    if count == 0 {
      if store.selectedIndex != nil {
        store.selectedIndex = nil
      }
      return
    }
    if let selectedIndex = store.selectedIndex, selectedIndex >= count {
      store.selectedIndex = count - 1
    } else if store.selectedIndex == nil {
      store.selectedIndex = 0
    }
  }

  private func moveSelection(_ direction: MoveCommandDirection, rows: [CommandPaletteItem]) {
    let count = rows.count
    guard count > 0 else {
      store.selectedIndex = nil
      return
    }
    let maxIndex = count - 1
    switch direction {
    case .up:
      if let selectedIndex = store.selectedIndex {
        store.selectedIndex = selectedIndex == 0 ? maxIndex : selectedIndex - 1
      } else {
        store.selectedIndex = maxIndex
      }
    case .down:
      if let selectedIndex = store.selectedIndex {
        store.selectedIndex = selectedIndex == maxIndex ? 0 : selectedIndex + 1
      } else {
        store.selectedIndex = 0
      }
    default:
      break
    }
  }

  private func submitSelected(rows: [CommandPaletteItem]) {
    let trimmed = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let selectedIndex = store.selectedIndex else {
      if let first = rows.first {
        store.send(.activate(first.kind))
      }
      return
    }
    if rows.indices.contains(selectedIndex) {
      store.send(.activate(rows[selectedIndex].kind))
      return
    }
    if let last = rows.last {
      store.send(.activate(last.kind))
    }
  }

  private func activateShortcut(_ index: Int, rows: [CommandPaletteItem]) {
    guard rows.indices.contains(index) else { return }
    store.send(.activate(rows[index].kind))
  }

  private func activate(_ id: CommandPaletteItem.ID, rows: [CommandPaletteItem]) {
    guard let item = rows.first(where: { $0.id == id }) else { return }
    store.send(.activate(item.kind))
  }
}

private struct CommandPaletteCard: View {
  @Binding var query: String
  @Binding var selectedIndex: Int?
  let items: [CommandPaletteItem]
  @Binding var hoveredID: CommandPaletteItem.ID?
  let isQueryFocused: FocusState<Bool>
  let onEvent: (CommandPaletteKeyboardEvent) -> Void
  let activateShortcut: (Int) -> Void
  let activate: (CommandPaletteItem.ID) -> Void

  private var backgroundColor: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  private var colorScheme: ColorScheme {
    NSColor.windowBackgroundColor.isLightColor ? .light : .dark
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      CommandPaletteQuery(query: $query, isTextFieldFocused: isQueryFocused) { event in
        onEvent(event)
      }

      Divider()

      CommandPaletteShortcutHandler(count: min(5, items.count)) { index in
        activateShortcut(index)
      }

      CommandPaletteList(
        rows: items,
        selectedIndex: $selectedIndex,
        hoveredID: $hoveredID
      ) { id in
        activate(id)
      }
    }
    .frame(maxWidth: 500)
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        Rectangle()
          .fill(backgroundColor)
          .blendMode(.color)
      }
      .compositingGroup()
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
    )
    .shadow(radius: 32, x: 0, y: 12)
    .padding()
    .environment(\.colorScheme, colorScheme)
  }
}

private enum CommandPaletteKeyboardEvent: Equatable {
  case exit
  case submit
  case move(MoveCommandDirection)
}

private struct CommandPaletteQuery: View {
  @Binding var query: String
  var onEvent: ((CommandPaletteKeyboardEvent) -> Void)?
  @FocusState private var isTextFieldFocused: Bool

  init(
    query: Binding<String>,
    isTextFieldFocused: FocusState<Bool>,
    onEvent: ((CommandPaletteKeyboardEvent) -> Void)? = nil
  ) {
    _query = query
    self.onEvent = onEvent
    _isTextFieldFocused = isTextFieldFocused
  }

  var body: some View {
    ZStack {
      Group {
        Button {
          onEvent?(.move(.up))
        } label: {
          Color.clear
        }
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut(.upArrow, modifiers: [])
        Button {
          onEvent?(.move(.down))
        } label: {
          Color.clear
        }
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut(.downArrow, modifiers: [])

        Button {
          onEvent?(.move(.up))
        } label: {
          Color.clear
        }
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut(.init("p"), modifiers: [.control])
        Button {
          onEvent?(.move(.down))
        } label: {
          Color.clear
        }
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut(.init("n"), modifiers: [.control])
      }
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)

      TextField("Execute a command…", text: $query)
        .padding()
        .font(.system(size: 20, weight: .light))
        .frame(height: 48)
        .textFieldStyle(.plain)
        .focused($isTextFieldFocused)
        .onChange(of: isTextFieldFocused) { focused in
          if !focused {
            onEvent?(.exit)
          }
        }
        .onExitCommand { onEvent?(.exit) }
        .onMoveCommand { onEvent?(.move($0)) }
        .onSubmit { onEvent?(.submit) }
    }
  }
}

private struct CommandPaletteList: View {
  let rows: [CommandPaletteItem]
  @Binding var selectedIndex: Int?
  @Binding var hoveredID: CommandPaletteItem.ID?
  let activate: (CommandPaletteItem.ID) -> Void

  var body: some View {
    if rows.isEmpty {
      Text("No matches")
        .foregroundStyle(.secondary)
        .padding()
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.1.id) { index, row in
              CommandPaletteRowView(
                row: row,
                shortcutIndex: index < 5 ? index : nil,
                isSelected: isRowSelected(index: index),
                hoveredID: $hoveredID
              ) {
                activate(row.id)
              }
              .id(row.id)
            }
          }
          .padding(10)
        }
        .frame(maxHeight: 200)
        .onChange(of: selectedIndex) { _ in
          guard let selectedIndex, rows.indices.contains(selectedIndex) else { return }
          proxy.scrollTo(rows[selectedIndex].id)
        }
      }
    }
  }

  private func isRowSelected(index: Int) -> Bool {
    guard let selectedIndex else { return false }
    if selectedIndex < rows.count {
      return selectedIndex == index
    }
    return index == rows.count - 1
  }
}

private struct CommandPaletteRowView: View {
  let row: CommandPaletteItem
  let shortcutIndex: Int?
  let isSelected: Bool
  @Binding var hoveredID: CommandPaletteItem.ID?
  let activate: () -> Void

  private var badge: String? {
    switch row.kind {
    case .openSettings, .newWorktree, .worktreeSelect:
      return nil
    case .runWorktree:
      return "Run"
    case .openWorktreeInEditor:
      return "Editor"
    case .removeWorktree:
      return "Remove"
    case .archiveWorktree:
      return "Archive"
    }
  }

  private var leadingIcon: String? {
    switch row.kind {
    case .openSettings:
      return "gearshape"
    case .newWorktree:
      return "plus"
    case .worktreeSelect:
      return nil
    case .runWorktree:
      return "play.fill"
    case .openWorktreeInEditor:
      return "pencil"
    case .removeWorktree:
      return "trash"
    case .archiveWorktree:
      return "archivebox"
    }
  }

  private var emphasis: Bool {
    switch row.kind {
    case .openSettings, .newWorktree:
      return true
    case .worktreeSelect, .runWorktree, .openWorktreeInEditor, .removeWorktree, .archiveWorktree:
      return false
    }
  }

  private var explicitShortcutSymbols: [String]? {
    switch row.kind {
    case .openSettings:
      return AppShortcuts.openSettings.displaySymbols
    case .newWorktree:
      return AppShortcuts.newWorktree.displaySymbols
    case .worktreeSelect, .runWorktree, .openWorktreeInEditor, .removeWorktree, .archiveWorktree:
      return nil
    }
  }

  var body: some View {
    Button(action: activate) {
      HStack(spacing: 8) {
        if let leadingIcon {
          Image(systemName: leadingIcon)
            .foregroundStyle(emphasis ? .primary : .secondary)
            .font(.system(size: 14, weight: .medium))
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(row.title)
            .fontWeight(emphasis ? .medium : .regular)

          if let subtitle = row.subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        if let badge, !badge.isEmpty {
          Text(badge)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
              Capsule().fill(Color(nsColor: .quaternaryLabelColor))
            )
            .foregroundStyle(.secondary)
        }

        if let explicitShortcutSymbols {
          ShortcutSymbolsView(symbols: explicitShortcutSymbols)
            .foregroundStyle(.secondary)
        } else if let shortcutIndex {
          ShortcutSymbolsView(symbols: commandPaletteShortcutSymbols(for: shortcutIndex))
            .foregroundStyle(.secondary)
        }
      }
      .padding(8)
      .contentShape(Rectangle())
      .background(rowBackground)
      .cornerRadius(5)
    }
    .buttonStyle(.plain)
    .help(helpText)
    .onHover { hovering in
      hoveredID = hovering ? row.id : nil
    }
  }

  private var rowBackground: some View {
    Group {
      if isSelected {
        Color(nsColor: .selectedContentBackgroundColor)
      } else if hoveredID == row.id {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
      } else {
        Color.clear
      }
    }
  }

  private var helpText: String {
    let base: String
    switch row.kind {
    case .worktreeSelect:
      base = "Switch to \(row.title)"
    case .openSettings:
      base = "Open Settings"
    case .newWorktree:
      base = "New Worktree"
    case .removeWorktree:
      base = "Remove \(row.title)"
    case .archiveWorktree:
      base = "Archive \(row.title)"
    case .runWorktree:
      base = "Run \(row.title)"
    case .openWorktreeInEditor:
      base = "Open \(row.title) in Editor"
    }
    if let explicitShortcutLabel {
      return "\(base) (\(explicitShortcutLabel))"
    }
    if let shortcutIndex {
      return "\(base) (\(commandPaletteShortcutLabel(for: shortcutIndex)))"
    }
    return base
  }

  private var explicitShortcutLabel: String? {
    switch row.kind {
    case .openSettings:
      return AppShortcuts.openSettings.display
    case .newWorktree:
      return AppShortcuts.newWorktree.display
    case .worktreeSelect, .runWorktree, .openWorktreeInEditor, .removeWorktree, .archiveWorktree:
      return nil
    }
  }
}

private struct ShortcutSymbolsView: View {
  let symbols: [String]

  var body: some View {
    HStack(spacing: 1) {
      ForEach(symbols, id: \.self) { symbol in
        Text(symbol)
          .frame(minWidth: 13)
      }
    }
  }
}

private struct CommandPaletteShortcutHandler: View {
  let count: Int
  let activate: (Int) -> Void

  var body: some View {
    Group {
      if count >= 1 {
        shortcutButton(index: 0)
      }
      if count >= 2 {
        shortcutButton(index: 1)
      }
      if count >= 3 {
        shortcutButton(index: 2)
      }
      if count >= 4 {
        shortcutButton(index: 3)
      }
      if count >= 5 {
        shortcutButton(index: 4)
      }
    }
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }

  private func shortcutButton(index: Int) -> some View {
    Button {
      activate(index)
    } label: {
      Color.clear
    }
    .buttonStyle(.plain)
    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
  }
}

private func commandPaletteShortcutSymbols(for index: Int) -> [String] {
  ["⌘", "\(index + 1)"]
}

private func commandPaletteShortcutLabel(for index: Int) -> String {
  "Cmd+\(index + 1)"
}

extension NSColor {
  fileprivate var isLightColor: Bool {
    luminance > 0.5
  }

  fileprivate var luminance: Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard let rgb = usingColorSpace(.sRGB) else { return 0 }
    rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (0.299 * red) + (0.587 * green) + (0.114 * blue)
  }
}
