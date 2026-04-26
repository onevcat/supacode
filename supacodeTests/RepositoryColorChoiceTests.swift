import Foundation
import Testing

@testable import supacode

struct RepositoryColorChoiceTests {
  @Test func paletteHasTenSystemColors() {
    // The fixed palette is part of the persistence contract: once
    // shipped, removing or renaming a case would break user JSON. This
    // test pins the count so an accidental rename or removal trips a
    // failure before release.
    #expect(RepositoryColorChoice.allCases.count == 10)
  }

  @Test func paletteCasesAreStable() {
    // Raw values are written to JSON; reordering allCases is fine but
    // case names are forever. Pin them.
    let names = RepositoryColorChoice.allCases.map(\.rawValue).sorted()
    #expect(
      names == [
        "blue",
        "cyan",
        "gray",
        "green",
        "mint",
        "orange",
        "pink",
        "purple",
        "red",
        "yellow",
      ]
    )
  }

  @Test func codableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for choice in RepositoryColorChoice.allCases {
      let data = try encoder.encode(choice)
      let decoded = try decoder.decode(RepositoryColorChoice.self, from: data)
      #expect(decoded == choice)
    }
  }

  @Test func displayNameNonEmpty() {
    for choice in RepositoryColorChoice.allCases {
      #expect(!choice.displayName.isEmpty)
    }
  }
}
