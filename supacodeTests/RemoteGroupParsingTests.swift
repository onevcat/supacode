import Testing

@testable import supacode

struct RemoteGroupParsingTests {
  @Test func parseGroup_uses_reuse_key_only() {
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux:alpha:1") == "alpha")
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux:Alpha Team:1") == "alpha-team")
    #expect(RemoteGroupParsing.parseGroup(from: "other:alpha:1") == nil)
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux::1") == nil)
  }
}
