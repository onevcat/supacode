import ComposableArchitecture
import SwiftUI

struct WorkflowHistoryPopoverButton: View {
  @Bindable var store: StoreOf<WorkflowStepHistoryFeature>
  let onIntent: (WorkflowRunPanelIntent) -> Void
  @State private var presented = false
  @State private var pinned = false
  @State private var hoveringButton = false
  @State private var hoveringPanel = false
  @State private var closeTask: Task<Void, Never>?

  var body: some View {
    Button {
      if pinned {
        presented = false
      } else {
        pinned = true
        presented = true
      }
    } label: {
      Image(systemName: "clock.arrow.circlepath")
    }
    .help("Workflow History. Hover to preview or click to keep open.")
    .accessibilityLabel("Workflow History")
    .onHover {
      hoveringButton = $0
      updateHover()
    }
    .popover(isPresented: $presented) {
      WorkflowStepHistoryView(store: store, onIntent: onIntent, onInteraction: { pinned = true })
        .onHover {
          hoveringPanel = $0
          updateHover()
        }
    }
    .onChange(of: presented) { _, visible in
      store.send(.setPresented(visible))
      if !visible {
        pinned = false
        hoveringPanel = false
      }
    }
    .onChange(of: store.openRequest) { _, _ in
      pinned = true
      presented = true
    }
    .onDisappear { closeTask?.cancel() }
  }

  private func updateHover() {
    closeTask?.cancel()
    if hoveringButton || hoveringPanel {
      presented = true
      return
    }
    guard !pinned else { return }
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(180))
      if !Task.isCancelled && !pinned { presented = false }
    }
  }
}
