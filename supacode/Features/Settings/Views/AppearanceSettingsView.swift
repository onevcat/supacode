import ComposableArchitecture
import SwiftUI

struct AppearanceSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section("Appearance") {
          HStack {
            let appearanceMode = $store.appearanceMode
            ForEach(AppearanceMode.allCases) { mode in
              AppearanceOptionCardView(
                mode: mode,
                isSelected: mode == appearanceMode.wrappedValue
              ) {
                appearanceMode.wrappedValue = mode
              }
            }
          }
        }
        Section("Quit") {
          Toggle(
            "Confirm before quitting",
            isOn: $store.confirmBeforeQuit
          )
          .help("Ask before quitting Supacode")
        }
        Section("Worktree") {
          Toggle(
            "Sort merged worktrees to bottom",
            isOn: $store.sortMergedWorktreesToBottom
          )
          .help("Move merged PR worktrees to the bottom of each repository list.")
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
