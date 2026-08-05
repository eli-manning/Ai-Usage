import AppKit
import SwiftUI

/// An `NSHostingView` that only accepts mouse events inside a caller-defined
/// region, letting clicks fall through to whatever is beneath the window
/// everywhere else. Hover tracking uses the same region so the large,
/// transparent panel frame cannot accidentally trigger expansion.
final class PillHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRegionProvider: (() -> CGRect)?
    var hoverRegionProvider: (() -> CGRect)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isInsideHoverRegion = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = hitTestRegionProvider else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        return provider().contains(localPoint) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverState(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    private func updateHoverState(with event: NSEvent) {
        guard let hoverRegionProvider else {
            setHovering(true)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        setHovering(hoverRegionProvider().contains(point))
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isInsideHoverRegion else { return }
        isInsideHoverRegion = hovering
        onHoverChanged?(hovering)
    }
}
