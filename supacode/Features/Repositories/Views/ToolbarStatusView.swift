import SwiftUI

struct ToolbarStatusView: View {
  let toast: RepositoriesFeature.StatusToast?
  let pullRequest: GithubPullRequest?

  @State private var measuredSize: CGSize?

  // Sequential crossfade: old content fades out first, then the width retargets
  // and the new content fades in. Avoids the messy middle state where both
  // messages sit on top of each other at partial opacity.
  private static let fadeOutDuration: Double = 0.14
  private static let widthDuration: Double = 0.22
  private static let fadeInDuration: Double = 0.18

  private static let transition: AnyTransition = .asymmetric(
    insertion: .opacity.animation(
      .easeOut(duration: fadeInDuration).delay(fadeOutDuration + widthDuration * 0.5)
    ),
    removal: .opacity.animation(.easeIn(duration: fadeOutDuration))
  )
  private static let sizeAnimation: Animation = .easeInOut(duration: widthDuration)
    .delay(fadeOutDuration)

  var body: some View {
    ZStack {
      content
        .id(identityKey)
        .transition(Self.transition)
    }
    .frame(width: measuredSize?.width, height: measuredSize?.height)
    .clipped()
    // Hidden probe renders the current content at its intrinsic size so we
    // can drive `measuredSize` with an animation, yielding a smooth width
    // interpolation between consecutive toast messages.
    .background(
      content
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .background(
          GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, newSize in
              withAnimation(Self.sizeAnimation) {
                measuredSize = newSize
              }
            }
          }
        )
    )
    .animation(Self.sizeAnimation, value: identityKey)
  }

  @ViewBuilder
  private var content: some View {
    switch toast {
    case .inProgress(let message):
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case .success(let message):
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityHidden(true)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case .warning(let message):
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case nil:
      if let model = PullRequestStatusModel(pullRequest: pullRequest) {
        PullRequestStatusButton(model: model)
      } else {
        MotivationalStatusView()
      }
    }
  }

  // Derive a stable per-content identity so SwiftUI can transition not only when
  // the toast kind toggles but also when the message text changes between two
  // consecutive successes / warnings.
  private var identityKey: String {
    switch toast {
    case .inProgress(let message):
      return "progress:\(message)"
    case .success(let message):
      return "success:\(message)"
    case .warning(let message):
      return "warning:\(message)"
    case nil:
      if let number = pullRequest?.number {
        return "pr:\(number)"
      }
      return "idle"
    }
  }
}

private struct MotivationalStatusView: View {
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    TimelineView(.everyMinute) { context in
      let hour = Calendar.current.component(.hour, from: context.date)
      let style = timeStyle(for: hour)
      let commandPaletteHint = AppShortcuts.helpText(
        title: "Open Command Palette",
        commandID: AppShortcuts.CommandID.commandPalette,
        in: resolvedKeybindings
      )
      HStack(spacing: 8) {
        Image(systemName: style.icon)
          .foregroundStyle(style.color)
          .font(.callout)
          .accessibilityHidden(true)
        Text("\(context.date, format: .dateTime.hour().minute()) – \(commandPaletteHint)")
          .font(.footnote)
          .monospaced()
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct TimeStyle {
  let icon: String
  let color: Color
}

private func timeStyle(for hour: Int) -> TimeStyle {
  switch hour {
  case 6..<12:
    TimeStyle(icon: "sunrise.fill", color: .orange)
  case 12..<17:
    TimeStyle(icon: "sun.max.fill", color: .yellow)
  case 17..<21:
    TimeStyle(icon: "sunset.fill", color: .pink)
  default:
    TimeStyle(icon: "moon.stars.fill", color: .indigo)
  }
}
