import AppKit
import Testing

@testable import supacode

@MainActor
struct WorktreeTerminalTabsViewTests {
  @Test func deferredAutofocusSkipsActiveTextEditing() {
    #expect(
      WorktreeTerminalTabsView.shouldAutoFocusTerminal(
        firstResponder: NSTextView(),
        forceAutoFocus: false,
        respectsActiveTextInput: true
      ) == false
    )
  }

  @Test func deferredAutofocusStillAllowsRegularRecovery() {
    #expect(
      WorktreeTerminalTabsView.shouldAutoFocusTerminal(
        firstResponder: nil,
        forceAutoFocus: false,
        respectsActiveTextInput: true
      )
    )
  }

  @Test func deferredAutofocusDoesNotOverrideTextEditingEvenWhenForced() {
    #expect(
      WorktreeTerminalTabsView.shouldAutoFocusTerminal(
        firstResponder: NSTextView(),
        forceAutoFocus: true,
        respectsActiveTextInput: true
      ) == false
    )
  }

  @Test func immediateAutofocusAlsoSkipsActiveTextEditing() {
    #expect(
      WorktreeTerminalTabsView.shouldAutoFocusTerminal(
        firstResponder: NSTextView(),
        forceAutoFocus: false,
        respectsActiveTextInput: true
      ) == false
    )
  }
}
