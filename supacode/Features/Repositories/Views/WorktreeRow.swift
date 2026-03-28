import SwiftUI

struct WorktreeRow: View {
  let name: String
  let subtitle: String?
  let worktreeColor: WorktreeColor
  let isBusy: Bool
  let gitIconName: String
  let gitIconColor: Color
  let isArchiving: Bool
  let isDeleting: Bool
  let info: WorktreeInfoEntry?
  let pullRequestBadgeText: String?
  let showsPullRequestInfo: Bool
  let isRunScriptRunning: Bool
  let showsNotificationIndicator: Bool
  let notifications: [WorktreeTerminalNotification]
  let shortcutHint: String?

  enum WorktreeColor {
    case `default`
    case main
    case pinned
  }

  init(
    row: WorktreeRowModel,
    displayMode: WorktreeRowDisplayMode,
    hideSubtitle: Bool,
    hideSubtitleOnMatch: Bool,
    showsPullRequestInfo: Bool,
    isRunScriptRunning: Bool,
    showsNotificationIndicator: Bool,
    notifications: [WorktreeTerminalNotification],
    shortcutHint: String?
  ) {
    self.isArchiving = row.isArchiving
    self.isDeleting = row.isDeleting
    self.info = row.info
    self.showsPullRequestInfo = showsPullRequestInfo
    self.isRunScriptRunning = isRunScriptRunning
    self.showsNotificationIndicator = showsNotificationIndicator
    self.notifications = notifications
    self.shortcutHint = shortcutHint
    self.isBusy = row.isArchiving || row.isDeleting || row.isPending

    // Worktree color.
    self.worktreeColor =
      if row.isMainWorktree { .main } else if row.isPinned { .pinned } else { .default }

    // Title and subtitle based on display mode.
    let branchName = row.name
    let worktreeName = Self.worktreeName(for: row)
    let effectiveWorktreeName = worktreeName.isEmpty ? branchName : worktreeName
    switch displayMode {
    case .branchFirst:
      self.name = branchName
    case .worktreeFirst:
      self.name = effectiveWorktreeName
    }

    // Hide subtitle when the worktree name matches the branch name's last path component.
    let branchLastComponent = branchName.split(separator: "/").last.map(String.init) ?? branchName
    let isMatch = effectiveWorktreeName == branchLastComponent
    let rawSubtitle = displayMode == .branchFirst ? effectiveWorktreeName : branchName
    if hideSubtitle || (hideSubtitleOnMatch && isMatch) {
      self.subtitle = nil
    } else {
      self.subtitle = rawSubtitle
    }

    // Pull request display.
    let prDisplay = WorktreePullRequestDisplay(
      worktreeName: row.name,
      pullRequest: showsPullRequestInfo ? row.info?.pullRequest : nil
    )
    self.pullRequestBadgeText = prDisplay.pullRequestBadgeStyle?.text
    if let pullRequest = prDisplay.pullRequest {
      switch pullRequest.state.uppercased() {
      case "MERGED":
        self.gitIconName = "git-merge"
        self.gitIconColor = .purple
      case "CLOSED":
        self.gitIconName = "git-pull-request-closed"
        self.gitIconColor = .red
      case "OPEN" where pullRequest.isDraft:
        self.gitIconName = "git-pull-request-draft"
        self.gitIconColor = .secondary
      case "OPEN":
        self.gitIconName = "git-pull-request"
        let readiness = PullRequestMergeReadiness(pullRequest: pullRequest)
        self.gitIconColor = readiness.isBlocking ? .red : .green
      default:
        self.gitIconName = "git-branch"
        self.gitIconColor = .secondary
      }
    } else {
      self.gitIconName = "git-branch"
      self.gitIconColor = .secondary
    }
  }

  private static func worktreeName(for row: WorktreeRowModel) -> String {
    guard !row.isMainWorktree else { return "Default" }
    guard !row.isPending else { return row.detail }
    if row.id.contains("/") {
      let pathName = URL(fileURLWithPath: row.id).lastPathComponent
      guard pathName.isEmpty else { return pathName }
    }
    if !row.detail.isEmpty, row.detail != "." {
      let detailName = URL(fileURLWithPath: row.detail).lastPathComponent
      guard detailName.isEmpty || detailName == "." else { return detailName }
    }
    return row.name
  }

  var body: some View {
    Label {
      HStack(spacing: 6) {
        TitleView(
          name: name,
          subtitle: subtitle,
          worktreeColor: worktreeColor,
          isBusy: isBusy
        )
        Spacer(minLength: 0)
        TrailingView(
          shortcutHint: shortcutHint,
          info: info,
          isBusy: isBusy,
          showsPullRequestInfo: showsPullRequestInfo,
          pullRequestBadgeText: pullRequestBadgeText,
          isRunScriptRunning: isRunScriptRunning,
          showsNotificationIndicator: showsNotificationIndicator,
          notifications: notifications
        )
      }
    } icon: {
      IconView(
        isArchiving: isArchiving,
        isDeleting: isDeleting,
        gitIconName: gitIconName,
        gitIconColor: gitIconColor
      )
    }
    .labelStyle(.verticallyCentered)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 6)
  }
}

// MARK: - Title.

private struct TitleView: View {
  let name: String
  let subtitle: String?
  let worktreeColor: WorktreeRow.WorktreeColor
  let isBusy: Bool
  @Environment(\.backgroundProminence) private var backgroundProminence

  private var resolvedWorktreeColor: AnyShapeStyle {
    guard backgroundProminence != .increased else { return AnyShapeStyle(.secondary) }
    return switch worktreeColor {
    case .main: AnyShapeStyle(.yellow)
    case .pinned: AnyShapeStyle(.orange)
    case .default: AnyShapeStyle(.tertiary)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(name)
        .font(.body)
        .lineLimit(1)
        .shimmer(isActive: isBusy)
      if let subtitle {
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(resolvedWorktreeColor)
          .lineLimit(1)
      }
    }
  }
}

// MARK: - Icon.

private struct IconView: View {
  let isArchiving: Bool
  let isDeleting: Bool
  let gitIconName: String
  let gitIconColor: Color
  @Environment(\.backgroundProminence) private var backgroundProminence

  private var isEmphasized: Bool {
    backgroundProminence == .increased
  }

  private var resolvedName: String {
    if isArchiving { return "archivebox" }
    if isDeleting { return "trash" }
    return gitIconName
  }

  private var resolvedColor: AnyShapeStyle {
    guard !isEmphasized else { return AnyShapeStyle(.secondary) }
    if isArchiving { return AnyShapeStyle(.orange) }
    if isDeleting { return AnyShapeStyle(.red) }
    return AnyShapeStyle(gitIconColor)
  }

  private var isSystemImage: Bool {
    isArchiving || isDeleting
  }

  private var accessibilityLabel: String? {
    if isArchiving { return "Archiving" }
    if isDeleting { return "Deleting" }
    return nil
  }

  var body: some View {
    Group {
      if isSystemImage {
        Image(systemName: resolvedName)
      } else {
        Image(resolvedName)
          .renderingMode(.template)
      }
    }
    .foregroundStyle(resolvedColor)
    .accessibilityLabel(accessibilityLabel ?? "")
    .accessibilityHidden(accessibilityLabel == nil)
  }
}

// MARK: - Trailing.

private struct TrailingView: View {
  let shortcutHint: String?
  let info: WorktreeInfoEntry?
  let isBusy: Bool
  let showsPullRequestInfo: Bool
  let pullRequestBadgeText: String?
  let isRunScriptRunning: Bool
  let showsNotificationIndicator: Bool
  let notifications: [WorktreeTerminalNotification]

  var body: some View {
    if let shortcutHint {
      Text(shortcutHint)
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      HStack(spacing: 6) {
        if !isBusy {
          DiffStatsView(info: info)
          if showsPullRequestInfo, let pullRequestBadgeText {
            Text(pullRequestBadgeText)
              .font(.caption)
              .foregroundStyle(.secondary)
              .transition(.blurReplace)
          }
        }
        StatusIndicator(
          isRunScriptRunning: isRunScriptRunning,
          showsNotificationIndicator: showsNotificationIndicator,
          notifications: notifications
        )
      }
    }
  }
}

// MARK: - Diff stats.

private struct DiffStatsView: View {
  let info: WorktreeInfoEntry?
  @Environment(\.backgroundProminence) private var backgroundProminence

  var body: some View {
    let isEmphasized = backgroundProminence == .increased
    if let added = info?.addedLines, let removed = info?.removedLines, added + removed > 0 {
      HStack(spacing: 2) {
        Text("+\(added)")
          .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
        Text("-\(removed)")
          .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
      }
      .font(.caption)
      .monospacedDigit()
      .transition(.blurReplace)
    }
  }
}

// MARK: - Status indicator.

private struct StatusIndicator: View {
  let isRunScriptRunning: Bool
  let showsNotificationIndicator: Bool
  let notifications: [WorktreeTerminalNotification]
  @Environment(\.backgroundProminence) private var backgroundProminence
  @Environment(\.focusNotificationAction) private var focusNotificationAction: (WorktreeTerminalNotification) -> Void

  var body: some View {
    let isEmphasized = backgroundProminence == .increased
    if isRunScriptRunning || showsNotificationIndicator {
      ZStack {
        if isRunScriptRunning {
          PingDot(
            style: isEmphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.green),
            size: 6,
            showsSolidCenter: !showsNotificationIndicator
          )
        }
        if showsNotificationIndicator {
          NotificationPopoverButton(notifications: notifications) {
            Circle()
              .fill(.red)
              .frame(width: 6, height: 6)
              .accessibilityLabel("Unread notifications")
          }
          .zIndex(1)
        }
      }
      .transition(.blurReplace)
    }
  }
}

// MARK: - Vertically centered label style.

private struct VerticallyCenteredLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon
      configuration.title
    }
  }
}

extension LabelStyle where Self == VerticallyCenteredLabelStyle {
  static var verticallyCentered: VerticallyCenteredLabelStyle { .init() }
}

// MARK: - Shimmer effect.

private struct ShimmerModifier: ViewModifier {
  let isActive: Bool
  @State private var phase = false

  func body(content: Content) -> some View {
    content
      .mask(
        LinearGradient(
          colors: isActive ? [.black.opacity(0.6), .black, .black.opacity(0.6)] : [.black],
          startPoint: phase ? UnitPoint(x: 1, y: 1) : UnitPoint(x: -0.5, y: -0.5),
          endPoint: phase ? UnitPoint(x: 1.5, y: 1.5) : UnitPoint(x: 0, y: 0)
        )
      )
      .animation(
        isActive ? .linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false) : nil,
        value: phase
      )
      .task(id: isActive) { phase = isActive }
  }
}

extension View {
  func shimmer(isActive: Bool) -> some View {
    modifier(ShimmerModifier(isActive: isActive))
  }
}

// MARK: - Pulsing dot.

private struct PingDot<S: ShapeStyle>: View {
  let style: S
  let size: CGFloat
  let showsSolidCenter: Bool
  @State private var isPinging = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(style, lineWidth: 1)
        .frame(width: size, height: size)
        .scaleEffect(isPinging ? 2 : 1)
        .opacity(isPinging ? 0 : 0.6)
        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isPinging)
      if showsSolidCenter {
        Circle()
          .fill(style)
          .frame(width: size, height: size)
      }
    }
    .accessibilityLabel("Run script active")
    .task { isPinging = true }
  }
}

// MARK: - Focus notification environment.

private nonisolated let notificationEnvironmentLogger = SupaLogger("Notifications")

extension EnvironmentValues {
  @Entry var focusNotificationAction: (WorktreeTerminalNotification) -> Void = { _ in
    notificationEnvironmentLogger.warning("focusNotificationAction called but was never set in the environment.")
  }
}
