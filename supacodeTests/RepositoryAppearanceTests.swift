import Foundation
import Testing

@testable import supacode

struct RepositoryAppearanceTests {
  @Test func emptyHasBothNil() {
    #expect(RepositoryAppearance.empty.icon == nil)
    #expect(RepositoryAppearance.empty.color == nil)
    #expect(RepositoryAppearance.empty.isEmpty)
  }

  @Test func iconOnlyIsNotEmpty() {
    let appearance = RepositoryAppearance(icon: .sfSymbol("folder"), color: nil)
    #expect(!appearance.isEmpty)
  }

  @Test func colorOnlyIsNotEmpty() {
    let appearance = RepositoryAppearance(icon: nil, color: .blue)
    #expect(!appearance.isEmpty)
  }

  @Test func bothSetIsNotEmpty() {
    let appearance = RepositoryAppearance(icon: .sfSymbol("folder"), color: .blue)
    #expect(!appearance.isEmpty)
  }

  @Test func codableRoundTripWithBoth() throws {
    let original = RepositoryAppearance(
      icon: .sfSymbol("folder.fill"),
      color: .purple
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RepositoryAppearance.self, from: data)
    #expect(decoded == original)
  }

  @Test func codableRoundTripIconOnly() throws {
    let original = RepositoryAppearance(icon: .userImage(filename: "abc.svg"), color: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RepositoryAppearance.self, from: data)
    #expect(decoded == original)
  }

  @Test func codableRoundTripColorOnly() throws {
    let original = RepositoryAppearance(icon: nil, color: .green)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RepositoryAppearance.self, from: data)
    #expect(decoded == original)
  }

  @Test func codableRoundTripEmpty() throws {
    let data = try JSONEncoder().encode(RepositoryAppearance.empty)
    let decoded = try JSONDecoder().decode(RepositoryAppearance.self, from: data)
    #expect(decoded == .empty)
  }

  @Test func decodingExtraFieldsIsTolerated() throws {
    // Forward-compat: a future schema may add fields; older builds
    // shouldn't refuse to decode.
    let raw = Data(
      """
      {
        "icon": "folder",
        "color": "red",
        "futureField": "ignored"
      }
      """.utf8
    )
    let decoded = try JSONDecoder().decode(RepositoryAppearance.self, from: raw)
    #expect(decoded.icon == .sfSymbol("folder"))
    #expect(decoded.color == .red)
  }
}
