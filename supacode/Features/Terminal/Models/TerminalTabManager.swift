import Observation

@MainActor
@Observable
final class TerminalTabManager {
  var tabs: [TerminalTabItem] = []
  var selectedTabId: TerminalTabID?

  func createTab(title: String, icon: String?, isTitleLocked: Bool = false) -> TerminalTabID {
    let tab = TerminalTabItem(title: title, icon: icon, isTitleLocked: isTitleLocked)
    if let selectedTabId,
      let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabId })
    {
      tabs.insert(tab, at: selectedIndex + 1)
    } else {
      tabs.append(tab)
    }
    selectedTabId = tab.id
    return tab.id
  }

  func selectTab(_ id: TerminalTabID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    selectedTabId = id
  }

  func updateTitle(_ id: TerminalTabID, title: String) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    guard !tabs[index].isTitleLocked else { return }
    tabs[index].title = title
  }

  func overrideTitle(_ id: TerminalTabID, title: String) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].title = title
    tabs[index].isTitleLocked = true
  }

  func clearTitleOverride(_ id: TerminalTabID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].isTitleLocked = false
  }

  /// Auto-detection write path (e.g. `CommandIconMap`). Only applies
  /// when nothing has claimed the icon slot.
  func updateIcon(_ id: TerminalTabID, icon: String?) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    guard tabs[index].iconLock == .auto else { return }
    tabs[index].icon = icon
  }

  /// User picker path. Always wins, transitioning the slot to `.user`.
  func overrideIcon(_ id: TerminalTabID, icon: String) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].icon = icon
    tabs[index].iconLock = .user
  }

  /// "Reset to default" from the icon picker. Drops back to `.none`
  /// so the next auto-detected match can take over.
  func clearIconOverride(_ id: TerminalTabID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].iconLock = .auto
  }

  /// Run Script / Custom Command write path. Pins the icon to `.script`
  /// — strong enough to block auto-detection, weak enough to yield to
  /// a user-set `.user` lock.
  func setScriptIcon(_ id: TerminalTabID, icon: String) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    guard tabs[index].iconLock != .user else { return }
    tabs[index].icon = icon
    tabs[index].iconLock = .script
  }

  func updateDirty(_ id: TerminalTabID, isDirty: Bool) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].isDirty = isDirty
  }

  func reorderTabs(_ orderedIds: [TerminalTabID]) {
    let existingIds = Set(tabs.map(\.id))
    let incomingIds = Set(orderedIds)
    guard existingIds == incomingIds else { return }
    let map = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
    tabs = orderedIds.compactMap { map[$0] }
  }

  func closeTab(_ id: TerminalTabID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs.remove(at: index)
    guard selectedTabId == id else { return }
    if index > 0 {
      selectedTabId = tabs[index - 1].id
    } else if !tabs.isEmpty {
      selectedTabId = tabs[0].id
    } else {
      selectedTabId = nil
    }
  }

  func closeOthers(keeping id: TerminalTabID) {
    tabs = tabs.filter { $0.id == id }
    selectedTabId = tabs.first?.id
  }

  func closeToRight(of id: TerminalTabID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs = Array(tabs.prefix(index + 1))
    if let selectedTabId, !tabs.contains(where: { $0.id == selectedTabId }) {
      self.selectedTabId = tabs.last?.id
    }
  }

  func closeAll() {
    tabs.removeAll()
    selectedTabId = nil
  }
}
