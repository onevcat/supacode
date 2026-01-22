import Foundation
import GhosttyKit

@MainActor
final class GhosttySurfaceBridge {
  let state = GhosttySurfaceState()
  var surface: ghostty_surface_t?
  weak var surfaceView: GhosttySurfaceView?
  var onTitleChange: ((String) -> Void)?

  func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
    if handleTitleAndPath(action) { return false }
    if handleCommandStatus(action) { return false }
    if handleMouseAndLink(action) { return false }
    if handleSearchAndScroll(action) { return false }
    if handleSizeAndKey(action) { return false }
    if handleConfigAndShell(action) { return false }
    return false
  }

  func sendText(_ text: String) {
    guard let surface else { return }
    text.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(text.lengthOfBytes(using: .utf8)))
    }
  }

  func sendCommand(_ command: String) {
    let finalCommand = command.hasSuffix("\n") ? command : "\(command)\n"
    sendText(finalCommand)
  }

  func closeSurface() {
    surfaceView?.closeSurface()
  }

  private func handleTitleAndPath(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
      if let title = string(from: action.action.set_title.title) {
        state.title = title
        onTitleChange?(title)
      }
      return true

    case GHOSTTY_ACTION_PROMPT_TITLE:
      state.promptTitle = action.action.prompt_title
      return true

    case GHOSTTY_ACTION_PWD:
      state.pwd = string(from: action.action.pwd.pwd)
      return true

    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
      let note = action.action.desktop_notification
      state.desktopNotificationTitle = string(from: note.title)
      state.desktopNotificationBody = string(from: note.body)
      return true

    default:
      return false
    }
  }

  private func handleCommandStatus(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_PROGRESS_REPORT:
      let report = action.action.progress_report
      state.progressState = report.state
      state.progressValue = report.progress == -1 ? nil : Int(report.progress)
      return true

    case GHOSTTY_ACTION_COMMAND_FINISHED:
      let info = action.action.command_finished
      state.commandExitCode = info.exit_code == -1 ? nil : Int(info.exit_code)
      state.commandDuration = info.duration
      return true

    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
      let info = action.action.child_exited
      state.childExitCode = info.exit_code
      state.childExitTimeMs = info.timetime_ms
      return true

    case GHOSTTY_ACTION_READONLY:
      state.readOnly = action.action.readonly
      return true

    case GHOSTTY_ACTION_RING_BELL:
      state.bellCount += 1
      return true

    default:
      return false
    }
  }

  private func handleMouseAndLink(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_MOUSE_SHAPE:
      state.mouseShape = action.action.mouse_shape
      return true

    case GHOSTTY_ACTION_MOUSE_VISIBILITY:
      state.mouseVisibility = action.action.mouse_visibility
      return true

    case GHOSTTY_ACTION_MOUSE_OVER_LINK:
      let link = action.action.mouse_over_link
      state.mouseOverLink = string(from: link.url, length: link.len)
      return true

    case GHOSTTY_ACTION_RENDERER_HEALTH:
      state.rendererHealth = action.action.renderer_health
      return true

    case GHOSTTY_ACTION_OPEN_URL:
      let openUrl = action.action.open_url
      state.openUrlKind = openUrl.kind
      state.openUrl = string(from: openUrl.url, length: openUrl.len)
      return true

    case GHOSTTY_ACTION_COLOR_CHANGE:
      let change = action.action.color_change
      state.colorChangeKind = change.kind
      state.colorChangeR = change.r
      state.colorChangeG = change.g
      state.colorChangeB = change.b
      return true

    default:
      return false
    }
  }

  private func handleSearchAndScroll(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_SCROLLBAR:
      let scroll = action.action.scrollbar
      state.scrollbarTotal = scroll.total
      state.scrollbarOffset = scroll.offset
      state.scrollbarLength = scroll.len
      return true

    case GHOSTTY_ACTION_START_SEARCH:
      state.searchNeedle = string(from: action.action.start_search.needle)
      return true

    case GHOSTTY_ACTION_END_SEARCH:
      state.searchNeedle = nil
      return true

    case GHOSTTY_ACTION_SEARCH_TOTAL:
      state.searchTotal = Int(action.action.search_total.total)
      return true

    case GHOSTTY_ACTION_SEARCH_SELECTED:
      state.searchSelected = Int(action.action.search_selected.selected)
      return true

    default:
      return false
    }
  }

  private func handleSizeAndKey(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_SIZE_LIMIT:
      let sizeLimit = action.action.size_limit
      state.sizeLimitMinWidth = sizeLimit.min_width
      state.sizeLimitMinHeight = sizeLimit.min_height
      state.sizeLimitMaxWidth = sizeLimit.max_width
      state.sizeLimitMaxHeight = sizeLimit.max_height
      return true

    case GHOSTTY_ACTION_INITIAL_SIZE:
      let initial = action.action.initial_size
      state.initialSizeWidth = initial.width
      state.initialSizeHeight = initial.height
      return true

    case GHOSTTY_ACTION_CELL_SIZE:
      let cell = action.action.cell_size
      state.cellSizeWidth = cell.width
      state.cellSizeHeight = cell.height
      return true

    case GHOSTTY_ACTION_RESET_WINDOW_SIZE:
      state.resetWindowSizeCount += 1
      return true

    case GHOSTTY_ACTION_KEY_SEQUENCE:
      let seq = action.action.key_sequence
      state.keySequenceActive = seq.active
      state.keySequenceTrigger = seq.trigger
      return true

    case GHOSTTY_ACTION_KEY_TABLE:
      let table = action.action.key_table
      state.keyTableTag = table.tag
      switch table.tag {
      case GHOSTTY_KEY_TABLE_ACTIVATE:
        state.keyTableName = string(
          from: table.value.activate.name, length: table.value.activate.len)
      default:
        state.keyTableName = nil
      }
      return true

    default:
      return false
    }
  }

  private func handleConfigAndShell(_ action: ghostty_action_s) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_SECURE_INPUT:
      state.secureInput = action.action.secure_input
      return true

    case GHOSTTY_ACTION_FLOAT_WINDOW:
      state.floatWindow = action.action.float_window
      return true

    case GHOSTTY_ACTION_RELOAD_CONFIG:
      state.reloadConfigSoft = action.action.reload_config.soft
      return true

    case GHOSTTY_ACTION_CONFIG_CHANGE:
      state.configChangeCount += 1
      return true

    case GHOSTTY_ACTION_OPEN_CONFIG:
      state.openConfigCount += 1
      return true

    case GHOSTTY_ACTION_PRESENT_TERMINAL:
      state.presentTerminalCount += 1
      return true

    case GHOSTTY_ACTION_CLOSE_TAB:
      state.closeTabMode = action.action.close_tab_mode
      return true

    case GHOSTTY_ACTION_QUIT_TIMER:
      state.quitTimer = action.action.quit_timer
      return true

    default:
      return false
    }
  }

  private func string(from pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
  }

  private func string(from pointer: UnsafePointer<CChar>?, length: Int) -> String? {
    guard let pointer, length > 0 else { return nil }
    let data = Data(bytes: pointer, count: length)
    return String(data: data, encoding: .utf8)
  }

  private func string(from pointer: UnsafePointer<CChar>?, length: UInt) -> String? {
    string(from: pointer, length: Int(length))
  }

  private func string(from pointer: UnsafePointer<CChar>?, length: UInt64) -> String? {
    string(from: pointer, length: Int(length))
  }
}
