import CoreGraphics
import Foundation

/// Turns sliding along the bottom edge into scroll-wheel events, so a long
/// PDF or web page can be "jogged" quickly. Posting events needs the
/// Accessibility permission.
public final class ScrollController {
    public static let shared = ScrollController()

    /// Pixels scrolled for a slide across the full width of the trackpad.
    /// Bigger means faster.
    public var pixelsPerPadWidth: Double = 25000

    /// Sub-pixel leftovers, so slow slides do not round down to nothing.
    private var remainder: Double = 0

    private init() {}

    /// `delta` is the finger's horizontal travel in trackpad widths
    /// (positive = to the right). Sliding right scrolls down.
    public func scroll(byPadWidths delta: Double) {
        // Faster slides get a bigger multiplier (up to 5x), so a quick swipe
        // can jump through a long document while a slow one stays precise.
        let boost = 1 + min(abs(delta) * 80, 4)
        let exact = -delta * pixelsPerPadWidth * boost + remainder
        let whole = exact.rounded(.towardZero)
        remainder = exact - whole
        guard whole != 0 else { return }

        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(max(min(whole, 20000), -20000)),
            wheel2: 0,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    public func reset() {
        remainder = 0
    }
}
