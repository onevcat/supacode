import SwiftUI

struct WorktreeDetailTitleView: View {
  let branchName: String
  let onSubmit: (String) -> Void

  @State private var isEditing = false
  @State private var draftName = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    if isEditing {
      HStack(spacing: 6) {
        Image(systemName: "arrow.trianglehead.branch")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("Branch", text: $draftName)
          .textFieldStyle(.plain)
          .focused($isFocused)
          .onChange(of: draftName) { _, newValue in
            let filtered = String(newValue.filter { !$0.isWhitespace })
            if filtered != newValue {
              draftName = filtered
            }
          }
          .onSubmit { commit() }
          .onExitCommand { cancel() }
          .onChange(of: isFocused) { _, isFocused in
            if !isFocused {
              cancel()
            }
          }
      }
      .font(.headline)
      .monospaced()
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .task { isFocused = true }
      .help("Rename branch (Return to confirm)")
    } else {
      Button {
        beginEditing()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrow.trianglehead.branch")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Text(branchName)
        }
        .font(.headline)
        .monospaced()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
      }
      .buttonStyle(.plain)
      .help("Tap to rename branch")
    }
  }

  private func beginEditing() {
    draftName = branchName
    isEditing = true
  }

  private func cancel() {
    isEditing = false
    draftName = branchName
    isFocused = false
  }

  private func commit() {
    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    isEditing = false
    isFocused = false
    guard !trimmed.isEmpty else { return }
    if trimmed != branchName {
      onSubmit(trimmed)
    }
  }
}
