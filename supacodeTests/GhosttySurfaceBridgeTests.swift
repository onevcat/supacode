import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct GhosttySurfaceBridgeTests {
  @Test func desktopNotificationEmitsCallback() {
    let bridge = GhosttySurfaceBridge()
    var received: (String, String)?
    bridge.onDesktopNotification = { title, body in
      received = (title, body)
    }

    var action = ghostty_action_s()
    action.tag = GHOSTTY_ACTION_DESKTOP_NOTIFICATION
    let target = ghostty_target_s()

    "Title".withCString { titlePtr in
      "Body".withCString { bodyPtr in
        action.action.desktop_notification = ghostty_action_desktop_notification_s(
          title: titlePtr,
          body: bodyPtr
        )
        _ = bridge.handleAction(target: target, action: action)
      }
    }

    #expect(received?.0 == "Title")
    #expect(received?.1 == "Body")
  }

  @Test func willHandleActionForAppActionsDependsOnCallbacks() {
    let bridge = GhosttySurfaceBridge()
    var action = ghostty_action_s()

    action.tag = GHOSTTY_ACTION_NEW_TAB
    #expect(bridge.willHandleAction(action) == false)

    bridge.onNewTab = { true }
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_CLOSE_TAB
    #expect(bridge.willHandleAction(action) == false)

    bridge.onCloseTab = { _ in true }
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_GOTO_TAB
    #expect(bridge.willHandleAction(action) == false)

    bridge.onGotoTab = { _ in true }
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_MOVE_TAB
    #expect(bridge.willHandleAction(action) == false)

    bridge.onMoveTab = { _ in true }
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE
    #expect(bridge.willHandleAction(action) == false)

    bridge.onCommandPaletteToggle = { true }
    #expect(bridge.willHandleAction(action) == true)
  }

  @Test func willHandleActionForUndoRedoIsTrue() {
    let bridge = GhosttySurfaceBridge()
    var action = ghostty_action_s()

    action.tag = GHOSTTY_ACTION_UNDO
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_REDO
    #expect(bridge.willHandleAction(action) == true)
  }

  @Test func willHandleActionForSplitActionsDependsOnCallback() {
    let bridge = GhosttySurfaceBridge()
    var action = ghostty_action_s()

    action.tag = GHOSTTY_ACTION_NEW_SPLIT
    action.action.new_split = GHOSTTY_SPLIT_DIRECTION_RIGHT
    #expect(bridge.willHandleAction(action) == false)

    bridge.onSplitAction = { _ in true }
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_GOTO_SPLIT
    action.action.goto_split = GHOSTTY_GOTO_SPLIT_NEXT
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_RESIZE_SPLIT
    action.action.resize_split = ghostty_action_resize_split_s(
      amount: 1,
      direction: GHOSTTY_RESIZE_SPLIT_RIGHT
    )
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_EQUALIZE_SPLITS
    #expect(bridge.willHandleAction(action) == true)

    action.tag = GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM
    #expect(bridge.willHandleAction(action) == true)
  }
}
