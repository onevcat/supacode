import SwiftUI

struct XcodeStyleStatusView: View {
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.system(size: 14))
        .monospaced()
        .accessibilityHidden(true)

      Text("Build Succeeded")
        .font(.system(size: 12))
        .monospaced()
        .foregroundStyle(.secondary)

      Text("|")
        .font(.system(size: 12))
        .monospaced()
        .foregroundStyle(.quaternary)

      Text("Today at 2:34 PM")
        .font(.system(size: 12))
        .monospaced()
        .foregroundStyle(.tertiary)
    }
  }
}

struct NoGlassEffectModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(.identity)
    } else {
      content
    }
  }
}

struct XcodeStyleDiagnosticsView: View {
  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 5) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
          .font(.system(size: 12))
          .monospaced()
          .accessibilityHidden(true)
        Text("3")
          .font(.system(size: 12, weight: .medium, design: .monospaced))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))

      HStack(spacing: 5) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
          .font(.system(size: 12))
          .monospaced()
          .accessibilityHidden(true)
        Text("0")
          .font(.system(size: 12, weight: .medium, design: .monospaced))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }
    .padding(.trailing, 4)
  }
}

#Preview("Status View") {
  XcodeStyleStatusView()
    .padding()
}

#Preview("Diagnostics View") {
  XcodeStyleDiagnosticsView()
    .padding()
}
