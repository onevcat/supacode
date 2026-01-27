import SwiftUI

struct XcodeStyleStatusView: View {
  private static let morningMessages = [
    "Rise and shine!",
    "Fresh start, fresh code",
    "Morning momentum",
    "Let's build something great",
    "New day, new commits",
    "Coffee and code",
    "Early bird gets the merge",
    "Dawn of productivity",
    "Morning clarity",
    "Fresh perspective today",
    "Start strong",
    "Morning focus activated",
    "Ready to create",
    "New opportunities await",
    "Embrace the morning",
    "Clear mind, clean code",
    "Morning wins",
    "Seize the day",
    "First light, first commit",
    "A.M. excellence",
    "Bright ideas brewing",
    "Morning magic",
    "Early hours, great power",
    "Sunrise productivity",
    "Wake up and ship",
    "Morning motivation",
    "Fresh energy",
    "Day one mentality",
    "New dawn, new features",
    "Morning mastery",
    "Kickstart your code",
    "Rise and build",
    "Morning grind",
    "Early momentum",
    "Sunrise hustle",
    "A.M. flow state",
    "Morning creativity",
    "Start shipping",
    "Daybreak dedication",
    "Morning mode: ON",
    "Early wins matter",
    "Sunrise coding",
    "Morning builder",
    "Fresh repo, fresh day",
    "Dawn patrol",
    "Morning rhythm",
    "Early excellence",
    "Sunshine coding",
    "A.M. architect",
    "Morning maker",
  ]

  private static let afternoonMessages = [
    "Keep the flow going",
    "You're in the zone",
    "Crushing it today",
    "Steady progress",
    "One commit at a time",
    "Momentum building",
    "Peak productivity",
    "Afternoon excellence",
    "Deep in the code",
    "Making it happen",
    "Full steam ahead",
    "Midday mastery",
    "Flow state achieved",
    "Building momentum",
    "Afternoon focus",
    "Keep pushing forward",
    "In the groove",
    "Solid progress",
    "Afternoon hustle",
    "On a roll",
    "Making waves",
    "P.M. productivity",
    "Hitting stride",
    "Code is flowing",
    "Afternoon builder",
    "Stay focused",
    "Keep shipping",
    "Midday momentum",
    "Powering through",
    "Afternoon wins",
    "In the pocket",
    "Code warrior",
    "Stay sharp",
    "Keep creating",
    "Afternoon architect",
    "Building greatness",
    "Stay hungry",
    "Afternoon grind",
    "Keep iterating",
    "Midday magic",
    "Push forward",
    "Afternoon vibes",
    "Stay locked in",
    "Keep building",
    "P.M. power hour",
    "Afternoon rhythm",
    "Stay in flow",
    "Keep the streak",
    "Midday maker",
    "Afternoon energy",
  ]

  private static let eveningMessages = [
    "Wrapping up nicely",
    "Great work today",
    "Evening productivity",
    "Almost there",
    "Finish strong",
    "Golden hour coding",
    "Evening excellence",
    "Sunset shipping",
    "Wind down strong",
    "Evening momentum",
    "Day's end sprint",
    "Twilight coding",
    "Evening focus",
    "Final stretch",
    "Closing strong",
    "Evening builder",
    "Sunset productivity",
    "Last commits",
    "Evening grind",
    "Day well spent",
    "Evening wins",
    "Sunset hustle",
    "Finish what you started",
    "Evening push",
    "Day's final acts",
    "Twilight productivity",
    "Evening maker",
    "Sunset mode",
    "Strong finish ahead",
    "Evening dedication",
    "Last mile energy",
    "Dusk determination",
    "Evening rhythm",
    "Closing time wins",
    "Sunset sprint",
    "Evening craft",
    "Day's end magic",
    "Twilight builder",
    "Evening polish",
    "Sunset sessions",
    "Final hour focus",
    "Evening persistence",
    "Wrapping with pride",
    "Dusk productivity",
    "Evening closer",
    "Sunset strength",
    "Day's last push",
    "Twilight hustle",
    "Evening finisher",
    "Golden hour grind",
  ]

  private static let nightMessages = [
    "Night owl mode",
    "Quiet hours, deep work",
    "The code doesn't sleep",
    "Late night magic",
    "Burning the midnight oil",
    "Moonlit coding",
    "Night shift excellence",
    "Midnight momentum",
    "Silent productivity",
    "After hours hustle",
    "Night builder",
    "Starlight shipping",
    "Nocturnal focus",
    "Midnight maker",
    "Night vibes",
    "Dark mode life",
    "Late night wins",
    "Moonlight grind",
    "Night warrior",
    "Midnight clarity",
    "Night session",
    "Stars align for code",
    "Nocturnal excellence",
    "Night shift flow",
    "Midnight hustle",
    "Night craft",
    "After dark coding",
    "Lunar productivity",
    "Night architect",
    "Midnight rhythm",
    "Night dedication",
    "Stargazer coder",
    "Nocturnal builder",
    "Night persistence",
    "Midnight magic",
    "Night focus",
    "Dark hours, bright code",
    "Night runner",
    "Midnight drive",
    "Nighttime mastery",
    "Late night flow",
    "Moonlit progress",
    "Night grind",
    "Midnight momentum",
    "Night creator",
    "Starlight sessions",
    "Nocturnal grind",
    "Night prowler",
    "Midnight builder",
    "Night excellence",
  ]

  private static func style(for hour: Int) -> (icon: String, color: Color, messages: [String]) {
    switch hour {
    case 6..<12:
      return ("sunrise.fill", .orange, morningMessages)
    case 12..<17:
      return ("sun.max.fill", .yellow, afternoonMessages)
    case 17..<21:
      return ("sunset.fill", .pink, eveningMessages)
    default:
      return ("moon.stars.fill", .indigo, nightMessages)
    }
  }

  private static func message(for date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    let style = style(for: hour)
    let day = Calendar.current.component(.day, from: date)
    let index = (day + hour) % style.messages.count
    return style.messages[index]
  }

  var body: some View {
    TimelineView(.everyMinute) { context in
      let hour = Calendar.current.component(.hour, from: context.date)
      let style = Self.style(for: hour)
      HStack(spacing: 8) {
        Image(systemName: style.icon)
          .foregroundStyle(style.color)
          .font(.system(size: 14))
          .monospaced()
          .accessibilityHidden(true)

        Text(Self.message(for: context.date))
          .font(.system(size: 12))
          .monospaced()
          .foregroundStyle(.secondary)
      }
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
