import AppKit
import CoreGraphics

/// Real notch geometry for the pill style, kept as its own type
/// (`PillNotchGeometry`/`PillNotchLayout`) since the fan style already owns
/// a `NotchGeometry` with a very different shape (a bar sliver above the
/// notch, sized to fit a wedge fan) — this one instead sizes a panel that
/// sits directly over the physical notch itself and expands straight down
/// into a card, matching `notch-limits`' own geometry.
struct PillNotchGeometry {
    /// Frame of the notch itself, in screen coordinates (bottom-left
    /// origin, matching `NSScreen.frame`).
    let notchFrame: CGRect
    let screen: NSScreen

    /// Whether `screen` actually has a hardware notch. On non-notched
    /// screens we synthesize a small pill-sized region so the UI still has
    /// somewhere sensible to live.
    let hasPhysicalNotch: Bool

    static func current(preferredScreen: NSScreen? = nil) -> PillNotchGeometry? {
        let screen = preferredScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        guard let screen else { return nil }

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = right.minX - left.maxX
            let notchHeight = screen.safeAreaInsets.top
            let frame = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - notchHeight,
                width: max(notchWidth, 1),
                height: notchHeight
            )
            return PillNotchGeometry(notchFrame: frame, screen: screen, hasPhysicalNotch: true)
        }

        // Fallback for external / non-notched displays: a small synthetic
        // pill centered at the top, roughly menu-bar height.
        let fallbackWidth: CGFloat = 180
        let fallbackHeight: CGFloat = 32
        let frame = CGRect(
            x: screen.frame.midX - fallbackWidth / 2,
            y: screen.frame.maxY - fallbackHeight,
            width: fallbackWidth,
            height: fallbackHeight
        )
        return PillNotchGeometry(notchFrame: frame, screen: screen, hasPhysicalNotch: false)
    }
}

/// Computed pixel geometry shared between the AppKit panel (frame, hit
/// testing) and the SwiftUI content (view sizing).
struct PillNotchLayout {
    let notchFrame: CGRect
    let panelFrame: CGRect
    let collapsedSize: CGSize
    let expandedSize: CGSize
    let hasPhysicalNotch: Bool

    static func make(from geometry: PillNotchGeometry) -> PillNotchLayout {
        let expandedWidth: CGFloat = 560
        let expandedHeight: CGFloat = 316
        // Wide enough either side of the notch for the fan style's own
        // minimal badge-circle + percentage chip (`ProviderBadgeView`,
        // `ProviderPercentageLabel`), which the collapsed indicator reuses
        // as-is — the original notch-limits row of tiny dashes only needed
        // 28pt total.
        let collapsedWidth = geometry.notchFrame.width + 100
        // Same reserved-top-height math the fan style already uses
        // (`NotchGeometry.info`), so both styles sit exactly flush with the
        // real menu bar/notch instead of the pill running a few pixels
        // taller and spilling below it.
        let collapsedHeight = NotchGeometry.info(for: geometry.screen).reservedTopHeight

        let panelWidth = max(expandedWidth, collapsedWidth)
        let panelHeight = expandedHeight

        let panelFrame = CGRect(
            x: geometry.screen.frame.midX - panelWidth / 2,
            y: geometry.screen.frame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        return PillNotchLayout(
            notchFrame: geometry.notchFrame,
            panelFrame: panelFrame,
            collapsedSize: CGSize(width: collapsedWidth, height: collapsedHeight),
            expandedSize: CGSize(width: expandedWidth, height: expandedHeight),
            hasPhysicalNotch: geometry.hasPhysicalNotch
        )
    }

    /// Matches the visible collapsed pill's own footprint exactly —
    /// hovering or clicking anywhere on that visible bar expands it, same
    /// as the fan style's own `IslandShellView` (whose hover trigger is
    /// its whole rest-state bar, not just the bare notch pixels).
    ///
    /// `NSHostingView` uses a *flipped* coordinate system (confirmed via a
    /// quick `NSHostingView(...).isFlipped` check — true), so "the top of
    /// the window" is `y == 0`, not `y == panelFrame.height`. The original
    /// notch-limits math assumed the opposite (non-flipped) convention,
    /// which put its hotspot in the wrong place entirely — that's why
    /// hover felt broken rather than merely "too small."
    var collapsedHitRect: CGRect {
        CGRect(
            x: (panelFrame.width - collapsedSize.width) / 2,
            y: 0,
            width: collapsedSize.width,
            height: collapsedSize.height
        )
    }

    var expandedHitRect: CGRect {
        CGRect(origin: .zero, size: panelFrame.size)
    }
}
