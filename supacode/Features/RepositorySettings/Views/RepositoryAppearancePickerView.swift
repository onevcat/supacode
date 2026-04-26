import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// Inline section that drives a repository's icon and color choice.
/// Hosted at the top of `RepositorySettingsView`'s Form. The actual SF
/// Symbol picker is presented as a sheet via `TabIconPickerView`,
/// parameterised with `RepositoryIconPresets.presets` so the shared
/// picker code surfaces repo-flavored vocabulary instead of the
/// terminal one used by tab icons.
///
/// All mutations go through `RepositorySettingsFeature` actions —
/// never via direct `store.appearance.* = ...` writes — so the
/// `store_state_mutation_in_views` SwiftLint rule stays clean and
/// reducer tests can exercise every code path.
struct RepositoryAppearancePickerView: View {
  @Bindable var store: StoreOf<RepositorySettingsFeature>

  @State private var isSymbolPickerPresented = false
  @State private var isImageImporterPresented = false

  private let previewSize: CGFloat = 36
  private let dotSize: CGFloat = 22

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      iconRow
      colorRow
      if let message = store.appearanceImportError {
        importErrorBanner(message: message)
      }
    }
    .sheet(isPresented: $isSymbolPickerPresented) {
      TabIconPickerView(
        initialIcon: currentSymbolName,
        defaultIcon: "folder.fill",
        title: "Repository Icon",
        subtitle:
          "Pick a preset or enter any SF Symbol name. SVG and SF Symbol icons are tinted "
          + "with the repo color; PNG keeps its own colors.",
        presets: RepositoryIconPresets.presets,
        onApply: { applySymbolFromPicker($0) },
        onCancel: { isSymbolPickerPresented = false }
      )
    }
    .fileImporter(
      isPresented: $isImageImporterPresented,
      allowedContentTypes: [.png, .svg],
      allowsMultipleSelection: false
    ) { result in
      handleImageImportResult(result)
    }
  }

  // MARK: - Icon row

  @ViewBuilder
  private var iconRow: some View {
    HStack(alignment: .center, spacing: 12) {
      iconPreview
      VStack(alignment: .leading, spacing: 4) {
        Text("Icon")
          .font(.headline)
        Text(iconHelpText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      iconButtons
    }
  }

  @ViewBuilder
  private var iconPreview: some View {
    let frame = RoundedRectangle(cornerRadius: 8, style: .continuous)
    let fill = Color.secondary.opacity(0.12)
    Group {
      if let icon = store.appearance.icon {
        RepositoryIconImage(
          icon: icon,
          repositoryRootURL: store.rootURL,
          tintColor: tintColor,
          size: 22
        )
      } else {
        Image(systemName: "questionmark")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .frame(width: previewSize, height: previewSize)
    .background(fill, in: frame)
    .accessibilityLabel("Icon preview")
  }

  @ViewBuilder
  private var iconButtons: some View {
    HStack(spacing: 6) {
      Button("Choose Symbol…") {
        isSymbolPickerPresented = true
      }
      .help("Pick from a preset SF Symbol or enter any symbol name.")
      Button("Choose Image…") {
        isImageImporterPresented = true
      }
      .help("Import a PNG or SVG file as this repository's icon.")
      if store.appearance.icon != nil {
        Button("Clear Icon") {
          store.send(.setAppearanceIcon(nil))
        }
        .help("Remove the current icon and stop showing one for this repo.")
      }
    }
  }

  private var iconHelpText: String {
    switch store.appearance.icon {
    case .userImage(let filename) where !filename.lowercased().hasSuffix(".svg"):
      return "PNG icons keep their original colors and ignore the repo color."
    case .userImage:
      return "User-provided SVGs are tinted with the repo color."
    case .sfSymbol:
      return "SF Symbols pick up the repo color when one is set."
    case .bundledAsset:
      return "Bundled icons keep their original artwork."
    case nil:
      return "No icon set — the row in the sidebar shows just the repo name."
    }
  }

  private var tintColor: Color {
    store.appearance.color?.color ?? .accentColor
  }

  private var currentSymbolName: String? {
    if case .sfSymbol(let name) = store.appearance.icon {
      return name
    }
    return nil
  }

  // MARK: - Color row

  @ViewBuilder
  private var colorRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Color")
        .font(.headline)
      Text(
        "Tints the row in the sidebar, the shelf spine background, and the canvas card title bar."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        ForEach(RepositoryColorChoice.allCases, id: \.self) { choice in
          colorSwatch(for: choice)
        }
        noColorSwatch
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private func colorSwatch(for choice: RepositoryColorChoice) -> some View {
    let isSelected = store.appearance.color == choice
    Button {
      store.send(.setAppearanceColor(choice))
    } label: {
      Circle()
        .fill(choice.color)
        .frame(width: dotSize, height: dotSize)
        .overlay {
          Circle()
            .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
            .padding(2)
        }
        .help(choice.displayName)
        .accessibilityLabel(choice.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var noColorSwatch: some View {
    let isSelected = store.appearance.color == nil
    Button {
      store.send(.setAppearanceColor(nil))
    } label: {
      Circle()
        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        .frame(width: dotSize, height: dotSize)
        .overlay {
          Image(systemName: "slash.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .overlay {
          Circle()
            .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
            .padding(2)
        }
        .help("No color")
        .accessibilityLabel("No color")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Error banner

  @ViewBuilder
  private func importErrorBanner(message: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      Text(message)
        .font(.caption)
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
      Button("Dismiss") {
        store.send(.dismissAppearanceImportError)
      }
      .buttonStyle(.plain)
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.orange.opacity(0.12))
    )
  }

  // MARK: - Actions

  private func applySymbolFromPicker(_ name: String?) {
    isSymbolPickerPresented = false
    if let name {
      store.send(.setAppearanceIcon(.sfSymbol(name)))
    } else {
      store.send(.setAppearanceIcon(nil))
    }
  }

  private func handleImageImportResult(_ result: Result<[URL], Error>) {
    isImageImporterPresented = false
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      // `fileImporter` returns security-scoped URLs on macOS — we need
      // to start access before reading and stop it on the way out so
      // the import store can copy the bytes into the sandboxed app
      // support directory.
      let needsScope = url.startAccessingSecurityScopedResource()
      defer {
        if needsScope { url.stopAccessingSecurityScopedResource() }
      }
      store.send(.importUserImage(url))
    case .failure(let error):
      store.send(.userImageImportFailed(error.localizedDescription))
    }
  }
}
