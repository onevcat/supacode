import Testing

@testable import supacode

@MainActor
struct TerminalTabManagerTests {
  @Test func createTabInsertsAfterSelection() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "one", icon: nil)
    let second = manager.createTab(title: "two", icon: nil)
    manager.selectTab(first)
    let third = manager.createTab(title: "three", icon: nil)
    let ids = manager.tabs.map(\.id)
    #expect(ids == [first, third, second])
  }

  @Test func closeTabSelectsAdjacent() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "one", icon: nil)
    let second = manager.createTab(title: "two", icon: nil)
    let third = manager.createTab(title: "three", icon: nil)
    manager.selectTab(second)
    manager.closeTab(second)
    #expect(manager.tabs.map(\.id) == [first, third])
    #expect(manager.selectedTabId == first)
  }

  @Test func closeToRightRemovesTrailingTabs() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "one", icon: nil)
    let second = manager.createTab(title: "two", icon: nil)
    let third = manager.createTab(title: "three", icon: nil)
    manager.closeToRight(of: second)
    #expect(manager.tabs.map(\.id) == [first, second])
    #expect(manager.tabs.contains { $0.id == third } == false)
  }

  @Test func closeOthersLeavesSingleTab() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "one", icon: nil)
    let second = manager.createTab(title: "two", icon: nil)
    _ = manager.createTab(title: "three", icon: nil)
    manager.closeOthers(keeping: second)
    #expect(manager.tabs.map(\.id) == [second])
    #expect(manager.selectedTabId == second)
    #expect(manager.tabs.contains { $0.id == first } == false)
  }

  @Test func reorderTabsUsesProvidedOrder() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "one", icon: nil)
    let second = manager.createTab(title: "two", icon: nil)
    let third = manager.createTab(title: "three", icon: nil)
    manager.reorderTabs([third, first, second])
    #expect(manager.tabs.map(\.id) == [third, first, second])
  }

  @Test func updateDirtyUpdatesTabState() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: nil)
    manager.updateDirty(tabId, isDirty: true)
    #expect(manager.tabs.first?.isDirty == true)
    manager.updateDirty(tabId, isDirty: false)
    #expect(manager.tabs.first?.isDirty == false)
  }

  @Test func overrideIconLocksAndSetsIcon() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.overrideIcon(tabId, icon: "sparkles")
    #expect(manager.tabs.first?.icon == "sparkles")
    #expect(manager.tabs.first?.iconLock == .user)
  }

  @Test func updateIconRespectsLock() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.overrideIcon(tabId, icon: "sparkles")
    manager.updateIcon(tabId, icon: "terminal")
    #expect(manager.tabs.first?.icon == "sparkles")
  }

  @Test func clearIconOverrideUnlocksIcon() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.overrideIcon(tabId, icon: "sparkles")
    manager.clearIconOverride(tabId)
    #expect(manager.tabs.first?.iconLock == .auto)
    manager.updateIcon(tabId, icon: "play.fill")
    #expect(manager.tabs.first?.icon == "play.fill")
  }

  @Test func setScriptIconAppliesAndFlags() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.setScriptIcon(tabId, icon: "play.fill")
    #expect(manager.tabs.first?.icon == "play.fill")
    #expect(manager.tabs.first?.iconLock == .script)
  }

  @Test func updateIconYieldsToScriptLock() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.setScriptIcon(tabId, icon: "play.fill")
    manager.updateIcon(tabId, icon: "@asset:Npm")
    #expect(manager.tabs.first?.icon == "play.fill")
  }

  @Test func userOverrideSupersedesScriptLock() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.setScriptIcon(tabId, icon: "play.fill")
    manager.overrideIcon(tabId, icon: "sparkles")
    #expect(manager.tabs.first?.icon == "sparkles")
    #expect(manager.tabs.first?.iconLock == .user)
  }

  @Test func setScriptIconYieldsToUserLock() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.overrideIcon(tabId, icon: "sparkles")
    manager.setScriptIcon(tabId, icon: "play.fill")
    #expect(manager.tabs.first?.icon == "sparkles")
    #expect(manager.tabs.first?.iconLock == .user)
  }

  @Test func clearIconOverrideReleasesScriptLock() {
    let manager = TerminalTabManager()
    let tabId = manager.createTab(title: "one", icon: "terminal")
    manager.setScriptIcon(tabId, icon: "play.fill")
    manager.clearIconOverride(tabId)
    #expect(manager.tabs.first?.iconLock == .auto)
    manager.updateIcon(tabId, icon: "@asset:Npm")
    #expect(manager.tabs.first?.icon == "@asset:Npm")
  }
}
