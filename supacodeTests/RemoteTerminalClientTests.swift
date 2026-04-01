import Foundation
import Testing

@testable import supacode

struct RemoteTerminalClientTests {
  @Test func listSessions_appends_scope_query() {
    let base = URL(string: "https://example.com/mini-terminal/")!
    let url = RemoteTerminalClient.sessionsURL(for: base)
    #expect(
      url.absoluteString
        == "https://example.com/mini-terminal/api/v1/terminal/sessions?scope=multi-tmux"
    )
  }
}
