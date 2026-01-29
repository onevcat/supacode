//
//  ContentView.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(\.scenePhase) private var scenePhase
  @State private var leftSidebarVisibility: NavigationSplitViewVisibility = .all

  init(store: StoreOf<AppFeature>, terminalManager: WorktreeTerminalManager) {
    self.store = store
    self.terminalManager = terminalManager
  }

  var body: some View {
    let repositoriesStore = store.scope(state: \.repositories, action: \.repositories)
    NavigationSplitView(columnVisibility: $leftSidebarVisibility) {
      SidebarView(store: repositoriesStore, terminalManager: terminalManager)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } detail: {
      WorktreeDetailView(store: store, terminalManager: terminalManager)
    }
    .navigationSplitViewStyle(.automatic)
    .task {
      store.send(.task)
    }
    .onChange(of: scenePhase) { _, newValue in
      store.send(.scenePhaseChanged(newValue))
    }
    .fileImporter(
      isPresented: Binding(
        get: { store.repositories.isOpenPanelPresented },
        set: { store.send(.repositories(.setOpenPanelPresented($0))) }
      ),
      allowedContentTypes: [.folder],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        store.send(.repositories(.openRepositories(urls)))
      case .failure:
        store.send(
          .repositories(
            .presentAlert(
              title: "Unable to open folders",
              message: "Supacode could not read the selected folders."
            )
          )
        )
      }
    }
    .alert(store: repositoriesStore.scope(state: \.$alert, action: \.alert))
    .alert(store: store.scope(state: \.$alert, action: \.alert))
    .focusedSceneValue(\.toggleLeftSidebarAction, toggleLeftSidebar)
  }

  private func toggleLeftSidebar() {
    withAnimation(.easeInOut(duration: 0.2)) {
      leftSidebarVisibility = leftSidebarVisibility == .detailOnly ? .all : .detailOnly
    }
  }
}
