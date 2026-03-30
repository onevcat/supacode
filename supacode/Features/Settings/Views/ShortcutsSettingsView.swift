import AppKit
import ComposableArchitecture
import SwiftUI

struct ShortcutsSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  @State private var searchText = ""
  @State private var recordingCommandID: String?
  @State private var recorderMonitor: Any?
  @State private var invalidMessageByCommandID: [String: String] = [:]
  @State private var pendingConflict: ShortcutConflict?
  @State private var pendingOverride: PendingOverride?
  @State private var focusedConflictCommandID: String?
  @State private var hoveredRecorderCommandID: String?

  private var schema: KeybindingSchemaDocument {
    .appDefaultsV1
  }

  private var editableCommands: [KeybindingCommandSchema] {
    schema.commands.filter(\.allowUserOverride)
  }

  private var resolvedBindings: ResolvedKeybindingMap {
    KeybindingResolver.resolve(
      schema: .appResolverSchema(),
      userOverrides: store.keybindingUserOverrides
    )
  }

  private var visibleGroups: [ShortcutGroup] {
    ShortcutGroup.allCases.filter { !commands(for: $0).isEmpty }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        TextField("Search actions or shortcuts", text: $searchText)
          .textFieldStyle(.roundedBorder)

        Button("Reset All") {
          resetAllOverrides()
        }
        .disabled(store.keybindingUserOverrides.overrides.isEmpty)
      }

      HStack(spacing: 12) {
        Text("Command")
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("Status")
          .frame(width: 72, alignment: .leading)
        Text("Shortcut")
          .frame(width: 220, alignment: .leading)
        Color.clear
          .frame(width: 16, height: 1)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)

      List {
        ForEach(visibleGroups) { group in
          Section {
            ForEach(commands(for: group), id: \.id) { command in
              row(for: command)
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .listRowBackground(rowBackground(for: command.id))
            }
          } header: {
            HStack(alignment: .center, spacing: 8) {
              Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Spacer(minLength: 0)
              if hasOverrides(in: group) {
                Button("Reset Section") {
                  resetOverrides(in: group)
                }
                .buttonStyle(.link)
                .font(.caption)
              }
            }
          }
        }

        if visibleGroups.isEmpty {
          Text("No shortcuts found.")
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.inset)
      .environment(\.defaultMinListRowHeight, 32)
    }
    .onChange(of: recordingCommandID) { _, commandID in
      if commandID == nil {
        stopRecorderMonitor()
      } else {
        startRecorderMonitor()
      }
    }
    .onDisappear {
      stopRecorderMonitor()
    }
    .alert(
      "Shortcut Conflict",
      isPresented: isConflictAlertPresented,
      presenting: pendingConflict
    ) { conflict in
      Button("Replace", role: .destructive) {
        applyPendingOverride(replacingConflict: true)
      }
      Button("Show Conflict") {
        focusConflictCommand(conflict)
      }
      Button("Cancel", role: .cancel) {
        clearPendingConflict()
      }
    } message: { conflict in
      Text(
        "“\(conflict.newCommandTitle)” and “\(conflict.existingCommandTitle)” both use \(conflict.binding.display)."
          + "\n\nChoose Replace to keep the new binding and disable the conflicting one."
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func row(for command: KeybindingCommandSchema) -> some View {
    let isRecording = recordingCommandID == command.id
    let resolvedBinding = resolvedBindings.binding(for: command.id)?.binding
    let source = resolvedBindings.binding(for: command.id)?.source ?? .appDefault
    let hasOverride = store.keybindingUserOverrides.overrides[command.id] != nil
    let isHoveringRecorder = hoveredRecorderCommandID == command.id

    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .center, spacing: 12) {
        Text(command.title)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)

        sourceChip(source)
          .frame(width: 72, alignment: .leading)

        shortcutRecorderField(
          commandID: command.id,
          resolvedBinding: resolvedBinding,
          isRecording: isRecording,
          isHovering: isHoveringRecorder
        )
        .frame(width: 220, alignment: .leading)

        if hasOverride {
          Button {
            resetOverride(for: command.id)
          } label: {
            Image(systemName: "arrow.counterclockwise")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Reset to default")
        } else {
          Color.clear
            .frame(width: 16, height: 16)
        }
      }

      if isRecording {
        HStack(spacing: 8) {
          Text(
            "Recording: press a key with modifiers (⌘ ⇧ ⌥ ⌃). Return and arrow keys are supported. Press Esc to cancel."
          )
          Spacer(minLength: 0)
          Button("Cancel") {
            stopRecording()
          }
          .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let invalid = invalidMessageByCommandID[command.id] {
        Text(invalid)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(.vertical, 2)
  }

  private func rowBackground(for commandID: String) -> some View {
    let isFocused = focusedConflictCommandID == commandID
    return RoundedRectangle(cornerRadius: 6)
      .fill(isFocused ? Color.orange.opacity(0.15) : .clear)
  }

  private func shortcutRecorderField(
    commandID: String,
    resolvedBinding: Keybinding?,
    isRecording: Bool,
    isHovering: Bool
  ) -> some View {
    Button {
      toggleRecording(for: commandID)
    } label: {
      HStack(spacing: 6) {
        if isRecording {
          Image(systemName: "record.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }

        Text(shortcutRecorderTitle(resolvedBinding: resolvedBinding, isRecording: isRecording))
          .font(.body.monospaced())
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(shortcutRecorderForegroundColor(resolvedBinding: resolvedBinding, isRecording: isRecording))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(shortcutRecorderBorderColor(isRecording: isRecording, isHovering: isHovering), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        hoveredRecorderCommandID = commandID
      } else if hoveredRecorderCommandID == commandID {
        hoveredRecorderCommandID = nil
      }
    }
    .help(isRecording ? "Recording shortcut. Press Esc to cancel." : "Click to record a shortcut.")
  }

  private func shortcutRecorderTitle(resolvedBinding: Keybinding?, isRecording: Bool) -> String {
    if isRecording {
      return "Recording…"
    }
    return resolvedBinding?.display ?? "Unassigned"
  }

  private func shortcutRecorderForegroundColor(resolvedBinding: Keybinding?, isRecording: Bool) -> Color {
    if isRecording {
      return .accentColor
    }
    return resolvedBinding == nil ? .secondary : .primary
  }

  private func shortcutRecorderBorderColor(isRecording: Bool, isHovering: Bool) -> Color {
    if isRecording {
      return .accentColor
    }
    if isHovering {
      return Color(nsColor: .tertiaryLabelColor)
    }
    return Color(nsColor: .separatorColor)
  }

  private func sourceChip(_ source: KeybindingSource) -> some View {
    let isDefault = source == .appDefault
    let label = isDefault ? "Default" : "Defined"

    return Text(label)
      .font(.caption2.monospaced())
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule()
          .fill(isDefault ? Color(nsColor: .quaternaryLabelColor).opacity(0.25) : Color.accentColor.opacity(0.2))
      )
      .foregroundStyle(isDefault ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
  }

  private func commands(for group: ShortcutGroup) -> [KeybindingCommandSchema] {
    editableCommands
      .filter { ShortcutGroup.resolve(for: $0.id) == group }
      .filter(matchesSearch)
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  private func matchesSearch(_ command: KeybindingCommandSchema) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }

    if command.title.localizedCaseInsensitiveContains(query) {
      return true
    }
    if command.id.localizedCaseInsensitiveContains(query) {
      return true
    }
    if let display = resolvedBindings.binding(for: command.id)?.binding?.display,
      display.localizedCaseInsensitiveContains(query)
    {
      return true
    }
    return false
  }

  private func hasOverrides(in group: ShortcutGroup) -> Bool {
    let commandIDs = Set(commands(for: group).map(\.id))
    return store.keybindingUserOverrides.overrides.keys.contains { commandIDs.contains($0) }
  }

  private func toggleRecording(for commandID: String) {
    invalidMessageByCommandID[commandID] = nil
    focusedConflictCommandID = nil
    if recordingCommandID == commandID {
      recordingCommandID = nil
      return
    }
    recordingCommandID = commandID
  }

  private func stopRecording() {
    recordingCommandID = nil
  }

  private func startRecorderMonitor() {
    stopRecorderMonitor()
    recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
      guard let commandID = recordingCommandID else {
        return event
      }
      handleRecorderEvent(event, commandID: commandID)
      return nil
    }
  }

  private func stopRecorderMonitor() {
    if let recorderMonitor {
      NSEvent.removeMonitor(recorderMonitor)
      self.recorderMonitor = nil
    }
  }

  private func handleRecorderEvent(_ event: NSEvent, commandID: String) {
    if event.keyCode == 53 {  // Escape
      stopRecording()
      return
    }

    guard let keyToken = keyToken(for: event) else {
      invalidMessageByCommandID[commandID] = "Unsupported key. Use letters, numbers, punctuation, Return, or arrows."
      return
    }

    let modifiers = KeybindingModifiers(
      command: event.modifierFlags.contains(.command),
      shift: event.modifierFlags.contains(.shift),
      option: event.modifierFlags.contains(.option),
      control: event.modifierFlags.contains(.control)
    )

    guard !modifiers.isEmpty else {
      invalidMessageByCommandID[commandID] = "Shortcut must include at least one modifier key."
      return
    }

    let binding = Keybinding(key: keyToken, modifiers: modifiers)
    applyRecordedBinding(binding, to: commandID)
  }

  private func keyToken(for event: NSEvent) -> String? {
    switch event.keyCode {
    case 36, 76:
      return "return"
    case 123:
      return "arrow_left"
    case 124:
      return "arrow_right"
    case 125:
      return "arrow_down"
    case 126:
      return "arrow_up"
    default:
      break
    }

    if let physicalDigit = physicalDigitToken(for: event.keyCode) {
      return physicalDigit
    }

    guard let scalar = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
      return nil
    }

    return String(scalar).lowercased()
  }

  private func physicalDigitToken(for keyCode: UInt16) -> String? {
    switch keyCode {
    case 29, 82:
      return "digit_0"
    case 18, 83:
      return "digit_1"
    case 19, 84:
      return "digit_2"
    case 20, 85:
      return "digit_3"
    case 21, 86:
      return "digit_4"
    case 23, 87:
      return "digit_5"
    case 22, 88:
      return "digit_6"
    case 26, 89:
      return "digit_7"
    case 28, 91:
      return "digit_8"
    case 25, 92:
      return "digit_9"
    default:
      return nil
    }
  }

  private func applyRecordedBinding(_ binding: Keybinding, to commandID: String) {
    invalidMessageByCommandID[commandID] = nil
    focusedConflictCommandID = nil

    guard let command = editableCommands.first(where: { $0.id == commandID }) else {
      stopRecording()
      return
    }

    let conflict = firstConflict(
      commandID: commandID,
      binding: binding,
      policy: command.conflictPolicy
    )

    if let conflict {
      pendingConflict = conflict
      pendingOverride = PendingOverride(commandID: commandID, binding: binding)
      stopRecording()
      return
    }

    saveOverride(
      commandID: commandID,
      binding: binding,
      replaceConflictCommandID: nil
    )
    stopRecording()
  }

  private func firstConflict(
    commandID: String,
    binding: Keybinding,
    policy: KeybindingConflictPolicy
  ) -> ShortcutConflict? {
    guard policy == .warnAndPreferUserOverride else { return nil }

    var tentative = store.keybindingUserOverrides
    tentative.overrides[commandID] = KeybindingUserOverride(binding: binding)

    let resolved = KeybindingResolver.resolve(
      schema: .appResolverSchema(),
      userOverrides: tentative
    )

    for command in editableCommands where command.id != commandID {
      guard resolved.binding(for: command.id)?.binding == binding else { continue }
      let newTitle = editableCommands.first(where: { $0.id == commandID })?.title ?? commandID
      return ShortcutConflict(
        newCommandID: commandID,
        newCommandTitle: newTitle,
        existingCommandID: command.id,
        existingCommandTitle: command.title,
        binding: binding
      )
    }

    return nil
  }

  private func applyPendingOverride(replacingConflict: Bool) {
    guard let pendingOverride else {
      clearPendingConflict()
      return
    }

    let conflictCommandID = replacingConflict ? pendingConflict?.existingCommandID : nil
    saveOverride(
      commandID: pendingOverride.commandID,
      binding: pendingOverride.binding,
      replaceConflictCommandID: conflictCommandID
    )
    clearPendingConflict()
  }

  private func clearPendingConflict() {
    pendingConflict = nil
    pendingOverride = nil
  }

  private func focusConflictCommand(_ conflict: ShortcutConflict) {
    focusedConflictCommandID = conflict.existingCommandID
    searchText = conflict.existingCommandTitle
    clearPendingConflict()
  }

  private func saveOverride(
    commandID: String,
    binding: Keybinding,
    replaceConflictCommandID: String?
  ) {
    var overrides = store.keybindingUserOverrides
    overrides.overrides[commandID] = KeybindingUserOverride(binding: binding)

    if let replaceConflictCommandID {
      overrides.overrides[replaceConflictCommandID] = KeybindingUserOverride(binding: nil, isEnabled: false)
    }

    $store.keybindingUserOverrides.wrappedValue = overrides
  }

  private func resetOverride(for commandID: String) {
    var overrides = store.keybindingUserOverrides
    overrides.overrides.removeValue(forKey: commandID)
    $store.keybindingUserOverrides.wrappedValue = overrides
    invalidMessageByCommandID[commandID] = nil
    if recordingCommandID == commandID {
      stopRecording()
    }
  }

  private func resetOverrides(in group: ShortcutGroup) {
    let commandIDs = Set(commands(for: group).map(\.id))
    var overrides = store.keybindingUserOverrides
    overrides.overrides = overrides.overrides.filter { !commandIDs.contains($0.key) }
    $store.keybindingUserOverrides.wrappedValue = overrides

    for commandID in commandIDs {
      invalidMessageByCommandID.removeValue(forKey: commandID)
    }

    if let recordingCommandID, commandIDs.contains(recordingCommandID) {
      stopRecording()
    }
  }

  private func resetAllOverrides() {
    $store.keybindingUserOverrides.wrappedValue = .empty
    invalidMessageByCommandID.removeAll()
    stopRecording()
  }

  private var isConflictAlertPresented: Binding<Bool> {
    Binding(
      get: { pendingConflict != nil },
      set: { shouldPresent in
        if !shouldPresent {
          clearPendingConflict()
        }
      }
    )
  }
}

private struct ShortcutConflict: Equatable {
  let newCommandID: String
  let newCommandTitle: String
  let existingCommandID: String
  let existingCommandTitle: String
  let binding: Keybinding
}

private struct PendingOverride: Equatable {
  let commandID: String
  let binding: Keybinding
}

private enum ShortcutGroup: String, CaseIterable, Identifiable {
  case general
  case navigation
  case terminal
  case scripts

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .general:
      "General"
    case .navigation:
      "Navigation"
    case .terminal:
      "Terminal Tabs & Panes"
    case .scripts:
      "Scripts & Panels"
    }
  }

  static func resolve(for commandID: String) -> ShortcutGroup {
    switch commandID {
    case AppShortcuts.CommandID.selectNextWorktree,
      AppShortcuts.CommandID.selectPreviousWorktree,
      AppShortcuts.CommandID.renameBranch,
      AppShortcuts.CommandID.selectWorktree1,
      AppShortcuts.CommandID.selectWorktree2,
      AppShortcuts.CommandID.selectWorktree3,
      AppShortcuts.CommandID.selectWorktree4,
      AppShortcuts.CommandID.selectWorktree5,
      AppShortcuts.CommandID.selectWorktree6,
      AppShortcuts.CommandID.selectWorktree7,
      AppShortcuts.CommandID.selectWorktree8,
      AppShortcuts.CommandID.selectWorktree9,
      AppShortcuts.CommandID.selectWorktree0:
      return .navigation

    case AppShortcuts.CommandID.runScript,
      AppShortcuts.CommandID.stopScript,
      AppShortcuts.CommandID.showDiff,
      AppShortcuts.CommandID.toggleCanvas,
      AppShortcuts.CommandID.selectAllCanvasCards,
      AppShortcuts.CommandID.archivedWorktrees:
      return .scripts

    case AppShortcuts.CommandID.selectTerminalTab1,
      AppShortcuts.CommandID.selectTerminalTab2,
      AppShortcuts.CommandID.selectTerminalTab3,
      AppShortcuts.CommandID.selectTerminalTab4,
      AppShortcuts.CommandID.selectTerminalTab5,
      AppShortcuts.CommandID.selectTerminalTab6,
      AppShortcuts.CommandID.selectTerminalTab7,
      AppShortcuts.CommandID.selectTerminalTab8,
      AppShortcuts.CommandID.selectTerminalTab9,
      AppShortcuts.CommandID.selectTerminalTab0,
      AppShortcuts.CommandID.selectPreviousTerminalTab,
      AppShortcuts.CommandID.selectNextTerminalTab,
      AppShortcuts.CommandID.selectPreviousTerminalPane,
      AppShortcuts.CommandID.selectNextTerminalPane,
      AppShortcuts.CommandID.selectTerminalPaneUp,
      AppShortcuts.CommandID.selectTerminalPaneDown,
      AppShortcuts.CommandID.selectTerminalPaneLeft,
      AppShortcuts.CommandID.selectTerminalPaneRight:
      return .terminal

    default:
      return .general
    }
  }
}
