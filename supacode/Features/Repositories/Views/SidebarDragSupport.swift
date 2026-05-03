import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  nonisolated static let prowlSidebarDragPayload = UTType.plainText
}

enum SidebarDragProvider {
  private nonisolated static let repositoryPrefix = "prowl-sidebar-repository:"
  private nonisolated static let worktreePrefix = "prowl-sidebar-worktree:"

  nonisolated static func repository(id: Repository.ID) -> NSItemProvider {
    itemProvider(payload: repositoryPrefix + id)
  }

  nonisolated static func worktree(id: Worktree.ID) -> NSItemProvider {
    itemProvider(payload: worktreePrefix + id)
  }

  nonisolated static func repositoryID(from data: Data) -> Repository.ID? {
    payload(from: data, prefix: repositoryPrefix)
  }

  nonisolated static func worktreeID(from data: Data) -> Worktree.ID? {
    payload(from: data, prefix: worktreePrefix)
  }

  private nonisolated static func itemProvider(payload: String) -> NSItemProvider {
    let provider = NSItemProvider()
    let loadHandler: (@escaping (Data?, (any Error)?) -> Void) -> Progress? = { completion in
      completion(Data(payload.utf8), nil)
      return nil
    }
    provider.registerDataRepresentation(
      forTypeIdentifier: UTType.prowlSidebarDragPayload.identifier,
      visibility: .all,
      loadHandler: loadHandler
    )
    return provider
  }

  private nonisolated static func payload(from data: Data, prefix: String) -> String? {
    guard let payload = String(data: data, encoding: .utf8),
      payload.hasPrefix(prefix)
    else {
      return nil
    }
    return String(payload.dropFirst(prefix.count))
  }
}

struct SidebarRepositoryDropDelegate: DropDelegate {
  let destination: (DropInfo) -> Int
  let repositoryOrderIDs: [Repository.ID]
  @Binding var targetedDestination: Int?
  let onDrop: (IndexSet, Int) -> Void
  let onDragEnded: () -> Void

  func dropEntered(info: DropInfo) {
    targetedDestination = destination(info)
  }

  func dropExited(info: DropInfo) {
    targetedDestination = nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    targetedDestination = destination(info)
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    let dropDestination = destination(info)
    targetedDestination = nil
    guard let provider = info.itemProviders(for: [.prowlSidebarDragPayload]).first else {
      onDragEnded()
      return false
    }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.prowlSidebarDragPayload.identifier) { data, _ in
      guard let data,
        let repositoryID = SidebarDragProvider.repositoryID(from: data),
        let source = repositoryOrderIDs.firstIndex(of: repositoryID),
        source != dropDestination,
        source + 1 != dropDestination
      else {
        Task { @MainActor in onDragEnded() }
        return
      }
      Task { @MainActor in
        onDrop(IndexSet(integer: source), dropDestination)
        onDragEnded()
      }
    }
    return true
  }
}

struct SidebarWorktreeDropDelegate: DropDelegate {
  let destination: (DropInfo) -> Int
  let sectionIDs: [Worktree.ID]
  @Binding var targetedDestination: Int?
  let onDrop: (IndexSet, Int) -> Void
  let onDragEnded: () -> Void

  func dropEntered(info: DropInfo) {
    targetedDestination = destination(info)
  }

  func dropExited(info: DropInfo) {
    targetedDestination = nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    targetedDestination = destination(info)
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    let dropDestination = destination(info)
    targetedDestination = nil
    guard let provider = info.itemProviders(for: [.prowlSidebarDragPayload]).first else {
      onDragEnded()
      return false
    }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.prowlSidebarDragPayload.identifier) { data, _ in
      guard let data,
        let worktreeID = SidebarDragProvider.worktreeID(from: data),
        let source = sectionIDs.firstIndex(of: worktreeID),
        source != dropDestination,
        source + 1 != dropDestination
      else {
        Task { @MainActor in onDragEnded() }
        return
      }
      Task { @MainActor in
        onDrop(IndexSet(integer: source), dropDestination)
        onDragEnded()
      }
    }
    return true
  }
}

struct SidebarDropIndicator: View {
  let isVisible: Bool
  var horizontalPadding: CGFloat = 12

  var body: some View {
    ZStack {
      if isVisible {
        Capsule()
          .fill(Color.accentColor)
          .frame(height: 2)
          .padding(.horizontal, horizontalPadding)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 6)
    .accessibilityHidden(true)
  }
}

extension View {
  func repositoryDropTarget(
    index: Int,
    repositoryOrderIDs: [Repository.ID],
    targetedDestination: Binding<Int?>,
    onDrop: @escaping (IndexSet, Int) -> Void,
    onDragEnded: @escaping () -> Void
  ) -> some View {
    self
      .overlay(alignment: .top) {
        SidebarDropIndicator(isVisible: targetedDestination.wrappedValue == index)
      }
      .overlay(alignment: .bottom) {
        SidebarDropIndicator(isVisible: targetedDestination.wrappedValue == index + 1)
      }
      .onDrop(
        of: [.prowlSidebarDragPayload],
        delegate: SidebarRepositoryDropDelegate(
          destination: { info in
            info.location.y < 24 ? index : index + 1
          },
          repositoryOrderIDs: repositoryOrderIDs,
          targetedDestination: targetedDestination,
          onDrop: onDrop,
          onDragEnded: onDragEnded
        )
      )
  }

  func worktreeDropTarget(
    index: Int,
    rowIDs: [Worktree.ID],
    targetedDestination: Binding<Int?>,
    onDrop: @escaping (IndexSet, Int) -> Void,
    onDragEnded: @escaping () -> Void
  ) -> some View {
    self
      .overlay(alignment: .top) {
        SidebarDropIndicator(isVisible: targetedDestination.wrappedValue == index, horizontalPadding: 28)
      }
      .overlay(alignment: .bottom) {
        SidebarDropIndicator(isVisible: targetedDestination.wrappedValue == index + 1, horizontalPadding: 28)
      }
      .onDrop(
        of: [.prowlSidebarDragPayload],
        delegate: SidebarWorktreeDropDelegate(
          destination: { info in
            info.location.y < 18 ? index : index + 1
          },
          sectionIDs: rowIDs,
          targetedDestination: targetedDestination,
          onDrop: onDrop,
          onDragEnded: onDragEnded
        )
      )
  }

  @ViewBuilder
  func draggableRepository(
    id: Repository.ID,
    isEnabled: Bool,
    beginDrag: @escaping () -> Void
  ) -> some View {
    if isEnabled {
      self.onDrag {
        beginDrag()
        return SidebarDragProvider.repository(id: id)
      }
    } else {
      self
    }
  }

  @ViewBuilder
  func draggableWorktree(
    id: Worktree.ID,
    isEnabled: Bool,
    beginDrag: @escaping () -> Void
  ) -> some View {
    if isEnabled {
      self.onDrag {
        beginDrag()
        return SidebarDragProvider.worktree(id: id)
      }
    } else {
      self
    }
  }
}
