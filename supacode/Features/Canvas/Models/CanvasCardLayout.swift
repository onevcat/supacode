import CoreGraphics
import Foundation

struct CanvasCardLayout: Codable, Equatable, Hashable, Sendable {
  var positionX: CGFloat
  var positionY: CGFloat
  var width: CGFloat
  var height: CGFloat

  var position: CGPoint {
    get { CGPoint(x: positionX, y: positionY) }
    set {
      positionX = newValue.x
      positionY = newValue.y
    }
  }

  var size: CGSize {
    get { CGSize(width: width, height: height) }
    set {
      width = newValue.width
      height = newValue.height
    }
  }

  static let defaultSize = CGSize(width: 800, height: 550)

  init(position: CGPoint, size: CGSize = Self.defaultSize) {
    self.positionX = position.x
    self.positionY = position.y
    self.width = size.width
    self.height = size.height
  }
}

// MARK: - Card Packing

struct CanvasCardPacker {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  struct CardInfo {
    var key: String
    var size: CGSize
  }

  struct PackResult {
    var layouts: [String: CanvasCardLayout]
    var boundingSize: CGSize
  }

  /// The maximum card count for exhaustive row-break enumeration.
  private static let exhaustiveLimit = 20

  /// Pack cards to maximize the fitToView scale — cards appear as large as
  /// possible on screen.
  ///
  /// Two strategies compete: **waterfall** (equal-width columns, cards drop
  /// into the shortest column — great for varying heights) and **row-break**
  /// (cards flow left-to-right with centered rows — great for varying widths).
  /// The configuration with the highest `min(vW/bW, vH/bH)` wins.
  func pack(cards: [CardInfo], targetRatio: CGFloat) -> PackResult {
    guard !cards.isEmpty, targetRatio > 0 else {
      return PackResult(layouts: [:], boundingSize: .zero)
    }

    let columnWidth = cards.map(\.size.width).max()!
    var bestScale: CGFloat = -1
    var bestArea = CGFloat.infinity
    // Positive = waterfall column count, negative = row-break mask (offset by -1).
    var bestTag = 1

    // Strategy 1: Waterfall — try all column counts.
    for cols in 1...cards.count {
      let (boxW, boxH) = waterfallBoundingSize(cards: cards, columns: cols, columnWidth: columnWidth)
      let scale = min(targetRatio / boxW, 1.0 / boxH)
      let area = boxW * boxH
      if scale > bestScale || (scale == bestScale && area < bestArea) {
        bestScale = scale
        bestArea = area
        bestTag = cols
      }
    }

    // Strategy 2: Row-break — try all row configurations (exhaustive for small N).
    if cards.count <= Self.exhaustiveLimit {
      for mask in 0..<(1 << (cards.count - 1)) {
        let (boxW, boxH) = rowBreakBoundingSize(cards: cards, breakMask: mask)
        let scale = min(targetRatio / boxW, 1.0 / boxH)
        let area = boxW * boxH
        if scale > bestScale || (scale == bestScale && area < bestArea) {
          bestScale = scale
          bestArea = area
          bestTag = -(mask + 1)
        }
      }
    }

    if bestTag > 0 {
      return waterfallPack(cards: cards, columns: bestTag, columnWidth: columnWidth)
    } else {
      return rowBreakLayout(cards: cards, breakMask: -(bestTag + 1))
    }
  }

  // MARK: - Waterfall layout

  /// Compute bounding size for a waterfall layout without building layouts.
  private func waterfallBoundingSize(
    cards: [CardInfo],
    columns: Int,
    columnWidth: CGFloat
  ) -> (CGFloat, CGFloat) {
    var colHeights = Array(repeating: spacing, count: columns)
    for card in cards {
      let col = colHeights.enumerated().min(by: { $0.element < $1.element })!.offset
      colHeights[col] += card.size.height + titleBarHeight + spacing
    }
    let totalWidth = spacing + CGFloat(columns) * (columnWidth + spacing)
    let totalHeight = colHeights.max() ?? spacing
    return (totalWidth, totalHeight)
  }

  /// Place cards into equal-width columns, each card going to the shortest
  /// column. Cards are horizontally centered within their column.
  private func waterfallPack(
    cards: [CardInfo],
    columns: Int,
    columnWidth: CGFloat
  ) -> PackResult {
    var colHeights = Array(repeating: spacing, count: columns)
    var layouts: [String: CanvasCardLayout] = [:]

    for card in cards {
      let col = colHeights.enumerated().min(by: { $0.element < $1.element })!.offset
      let cardHeight = card.size.height + titleBarHeight
      let colLeft = spacing + CGFloat(col) * (columnWidth + spacing)

      layouts[card.key] = CanvasCardLayout(
        position: CGPoint(
          x: colLeft + columnWidth / 2,
          y: colHeights[col] + cardHeight / 2
        ),
        size: card.size
      )

      colHeights[col] += cardHeight + spacing
    }

    let totalWidth = spacing + CGFloat(columns) * (columnWidth + spacing)
    let totalHeight = colHeights.max() ?? spacing

    return PackResult(
      layouts: layouts,
      boundingSize: CGSize(width: totalWidth, height: totalHeight)
    )
  }

  // MARK: - Row-break layout

  /// Compute bounding size for a row-break configuration without allocating.
  private func rowBreakBoundingSize(cards: [CardInfo], breakMask: Int) -> (CGFloat, CGFloat) {
    var maxWidth = spacing
    var totalHeight = spacing
    var rowWidth = spacing
    var rowHeight: CGFloat = 0

    for idx in 0..<cards.count {
      if idx > 0 && (breakMask & (1 << (idx - 1))) != 0 {
        maxWidth = max(maxWidth, rowWidth)
        totalHeight += rowHeight + spacing
        rowWidth = spacing
        rowHeight = 0
      }
      rowWidth += cards[idx].size.width + spacing
      rowHeight = max(rowHeight, cards[idx].size.height + titleBarHeight)
    }

    maxWidth = max(maxWidth, rowWidth)
    totalHeight += rowHeight + spacing
    return (maxWidth, totalHeight)
  }

  /// Build card layouts from a row-break mask. Rows are centered horizontally.
  private func rowBreakLayout(cards: [CardInfo], breakMask: Int) -> PackResult {
    var rows: [[Int]] = [[0]]
    for idx in 1..<cards.count {
      if breakMask & (1 << (idx - 1)) != 0 {
        rows.append([idx])
      } else {
        rows[rows.count - 1].append(idx)
      }
    }

    let rowWidths = rows.map { row -> CGFloat in
      row.reduce(spacing) { $0 + cards[$1].size.width + spacing }
    }
    let maxRowWidth = rowWidths.max() ?? 0

    var layouts: [String: CanvasCardLayout] = [:]
    var posY = spacing

    for (rowIndex, row) in rows.enumerated() {
      let rowHeight = row.map { cards[$0].size.height + titleBarHeight }.max() ?? 0
      let xOffset = (maxRowWidth - rowWidths[rowIndex]) / 2
      var posX = spacing + xOffset

      for idx in row {
        let card = cards[idx]
        let cardHeight = card.size.height + titleBarHeight
        layouts[card.key] = CanvasCardLayout(
          position: CGPoint(
            x: posX + card.size.width / 2,
            y: posY + cardHeight / 2
          ),
          size: card.size
        )
        posX += card.size.width + spacing
      }

      posY += rowHeight + spacing
    }

    return PackResult(
      layouts: layouts,
      boundingSize: CGSize(width: maxRowWidth, height: posY)
    )
  }
}

@MainActor
@Observable
final class CanvasLayoutStore {
  private static let storageKey = "canvasCardLayouts"

  /// Whether auto-arrange has run in this app session. Resets on app launch.
  static var hasAutoArrangedInSession = false

  var cardLayouts: [String: CanvasCardLayout] {
    didSet { save() }
  }

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let layouts = try? JSONDecoder().decode([String: CanvasCardLayout].self, from: data)
    {
      self.cardLayouts = layouts
    } else {
      self.cardLayouts = [:]
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(cardLayouts) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
