import ComposableArchitecture
import PostHog
import SwiftUI

struct AnalyticsClient {
  var capture: @Sendable (_ event: String, _ properties: [String: Any]?) -> Void
  var identify: @Sendable (_ distinctId: String) -> Void
}

extension AnalyticsClient: DependencyKey {
  static let liveValue = AnalyticsClient(
    capture: { event, properties in
      #if !DEBUG
        PostHogSDK.shared.capture(event, properties: properties)
      #endif
    },
    identify: { distinctId in
      #if !DEBUG
        PostHogSDK.shared.identify(distinctId)
      #endif
    }
  )

  static let testValue = AnalyticsClient(
    capture: { _, _ in },
    identify: { _ in }
  )
}

extension DependencyValues {
  var analyticsClient: AnalyticsClient {
    get { self[AnalyticsClient.self] }
    set { self[AnalyticsClient.self] = newValue }
  }
}

private struct AnalyticsClientKey: EnvironmentKey {
  static let defaultValue = AnalyticsClient.liveValue
}

extension EnvironmentValues {
  var analyticsClient: AnalyticsClient {
    get { self[AnalyticsClientKey.self] }
    set { self[AnalyticsClientKey.self] = newValue }
  }
}
