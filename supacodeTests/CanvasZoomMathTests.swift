import CoreGraphics
import Foundation
import Testing

@testable import supacode

struct CanvasZoomMathTests {
  @Test func positiveDeltaIncreasesScale() {
    let result = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale > 1.0)
  }

  @Test func negativeDeltaDecreasesScale() {
    let result = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: -10,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale < 1.0)
  }

  @Test func scaleIsClampedToMaximum() {
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.maxScale,
      currentOffset: .zero,
      deltaY: 1000,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale == CanvasZoomMath.maxScale)
  }

  @Test func scaleIsClampedToMinimum() {
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.minScale,
      currentOffset: .zero,
      deltaY: -1000,
      anchor: .zero,
      isPrecise: false
    )

    #expect(result.scale == CanvasZoomMath.minScale)
  }

  @Test func anchorPointStaysPutAfterZoom() {
    // The canvas point under the anchor must map to the same screen position
    // before and after zooming. Using `screen = canvas * scale + offset`,
    // the canvas point under `anchor` is `(anchor - offset) / scale`. After
    // applying the new scale and offset, it must still land on `anchor`.
    let currentScale: CGFloat = 1.0
    let currentOffset = CGSize(width: 50, height: 30)
    let anchor = CGPoint(x: 200, y: 150)

    let result = CanvasZoomMath.zoom(
      currentScale: currentScale,
      currentOffset: currentOffset,
      deltaY: 25,
      anchor: anchor,
      isPrecise: false
    )

    let canvasX = (anchor.x - currentOffset.width) / currentScale
    let canvasY = (anchor.y - currentOffset.height) / currentScale
    let projectedX = canvasX * result.scale + result.offset.width
    let projectedY = canvasY * result.scale + result.offset.height

    #expect(abs(projectedX - anchor.x) < 0.0001)
    #expect(abs(projectedY - anchor.y) < 0.0001)
  }

  @Test func clampedScaleLeavesOffsetUnchanged() {
    // When the new scale is clamped to the same as the current scale, the
    // offset should not drift — otherwise the canvas would jump even though
    // the zoom did nothing.
    let currentOffset = CGSize(width: 100, height: 80)
    let result = CanvasZoomMath.zoom(
      currentScale: CanvasZoomMath.maxScale,
      currentOffset: currentOffset,
      deltaY: 50,
      anchor: CGPoint(x: 300, y: 200),
      isPrecise: false
    )

    #expect(result.offset == currentOffset)
    #expect(result.scale == CanvasZoomMath.maxScale)
  }

  @Test func preciseScrollUsesGentlerSensitivity() {
    let imprecise = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: false
    )
    let precise = CanvasZoomMath.zoom(
      currentScale: 1.0,
      currentOffset: .zero,
      deltaY: 10,
      anchor: .zero,
      isPrecise: true
    )

    #expect(precise.scale < imprecise.scale)
    #expect(precise.scale > 1.0)
  }
}
