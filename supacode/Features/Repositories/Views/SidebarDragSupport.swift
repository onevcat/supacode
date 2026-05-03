import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let prowlSidebarRepositoryID = UTType(exportedAs: "com.onevcat.prowl.sidebar.repository-id")
  static let prowlSidebarWorktreeID = UTType(exportedAs: "com.onevcat.prowl.sidebar.worktree-id")
}

enum SidebarDragProvider {
  static func repository(id: Repository.ID) -> NSItemProvider {
    itemProvider(id: id, type: .prowlSidebarRepositoryID)
  }

  static func worktree(id: Worktree.ID) -> NSItemProvider {
    itemProvider(id: id, type: .prowlSidebarWorktreeID)
  }

  private static func itemProvider(id: String, type: UTType) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
      completion(Data(id.utf8), nil)
      return nil
    }
    return provider
  }
}

struct SidebarRepositoryDropDelegate: DropDelegate {
  let destination: Int
  let repositoryOrderIDs: [Repository.ID]
  @Binding var targetedDestination: Int?
  let onDrop: (IndexSet, Int) -> Void
  let onDragEnded: () -> Void

  func dropEntered(info: DropInfo) {
    targetedDestination = destination
  }

  func dropExited(info: DropInfo) {
    if targetedDestination == destination {
      targetedDestination = nil
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    targetedDestination = nil
    guard let provider = info.itemProviders(for: [.prowlSidebarRepositoryID]).first else {
      onDragEnded()
      return false
    }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.prowlSidebarRepositoryID.identifier) { data, _ in
      guard let data,
        let repositoryID = String(data: data, encoding: .utf8),
        let source = repositoryOrderIDs.firstIndex(of: repositoryID),
        source != destination,
        source + 1 != destination
      else {
        Task { @MainActor in onDragEnded() }
        return
      }
      Task { @MainActor in
        onDrop(IndexSet(integer: source), destination)
        onDragEnded()
      }
    }
    return true
  }
}

struct SidebarWorktreeDropDelegate: DropDelegate {
  let destination: Int
  let sectionIDs: [Worktree.ID]
  @Binding var targetedDestination: Int?
  let onDrop: (IndexSet, Int) -> Void
  let onDragEnded: () -> Void

  func dropEntered(info: DropInfo) {
    targetedDestination = destination
  }

  func dropExited(info: DropInfo) {
    if targetedDestination == destination {
      targetedDestination = nil
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    targetedDestination = nil
    guard let provider = info.itemProviders(for: [.prowlSidebarWorktreeID]).first else {
      onDragEnded()
      return false
    }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.prowlSidebarWorktreeID.identifier) { data, _ in
      guard let data,
        let worktreeID = String(data: data, encoding: .utf8),
        let source = sectionIDs.firstIndex(of: worktreeID),
        source != destination,
        source + 1 != destination
      else {
        Task { @MainActor in onDragEnded() }
        return
      }
      Task { @MainActor in
        onDrop(IndexSet(integer: source), destination)
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
