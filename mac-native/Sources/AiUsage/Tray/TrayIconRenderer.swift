import AppKit
import UsageCore

/// Draws the menu-bar badge.
///
/// os-menu had to render this by driving a hidden `BrowserWindow`'s canvas and
/// resizing the resulting bitmap — the tray icon literally could not be drawn
/// unless a renderer process was alive and finished loading. Here it's just
/// Core Graphics into an `NSImage`, which also means the badge is correct on
/// the very first paint instead of after the popup's first load.
enum TrayIconRenderer {

    /// Height of the bar the badge sits in.
    ///
    /// Deliberately *not* `NSStatusBar.system.thickness`, which reports 22 on
    /// a notched MacBook whose menu bar is really 32pt — sizing to it left the
    /// badge visibly undersized in the bar. `NotchGeometry` already resolves
    /// the true height (safe-area inset on notched displays, status-bar
    /// thickness elsewhere), so reuse it rather than keeping a second answer.
    private static var slotHeight: CGFloat { NotchGeometry.info().reservedTopHeight }

    /// How much of the bar's height the badge fills. Measured off the original
    /// badge, which sat 28pt tall in this machine's 32pt bar.
    private static let badgeFillRatio: CGFloat = 0.875
    private static var badgeSide: CGFloat { (slotHeight * badgeFillRatio).rounded() }

    // Everything below is expressed as a fraction of `badgeSide`, measured off
    // the original web build's badge. They're ratios rather than point sizes
    // so `badgeSide` stays the single knob: change it and the label, padding
    // and corner all rescale together instead of drifting out of proportion.
    //
    /// The label is sized to *fill* this much of the square's width, not to a
    /// fixed point size — so "5%" is set large, "94%" medium and "100%" small,
    /// each using the full width available to it rather than leaving the
    /// short ones swimming in empty space.
    private static let textWidthRatio: CGFloat = 0.82
    /// Ceiling on the width-driven size, per digit count. Without a ceiling a
    /// one-digit label grows until it fills the width and blows out of the
    /// square vertically.
    ///
    /// It varies by length rather than being one number because the width
    /// clamp alone doesn't separate the cases well: it leaves the short
    /// labels set noticeably heavier than the long ones, since fewer glyphs
    /// spread over the same width means each is taller. These are the tuned
    /// "big / medium / small" steps.
    private static func maxCapHeightRatio(forDigits digits: Int) -> CGFloat {
        switch digits {
        case ...1: return 0.40
        case 2: return 0.30
        default: return 0.26
        }
    }
    private static let cornerRadiusRatio: CGFloat = 0.18
    /// The placeholder shows a single glyph rather than 2-4, so it can afford
    /// to be set much larger than `capHeightRatio` — at the percentage's size
    /// one lone letter reads as a speck floating in a large square.
    private static let placeholderCapHeightRatio: CGFloat = 0.42
    /// How far the placeholder's fill is knocked back from the live badge's.
    /// Dimmed rather than hollow: an outline put the glyph on the dark menu
    /// bar instead of on the brand colour, which is what made it unreadable.
    private static let placeholderFillAlpha: CGFloat = 0.4
    /// Below this the digits stop being legible in the bar; at that point the
    /// label sheds its "%" rather than shrinking further.
    private static let minFontSize: CGFloat = 5.5

    /// Condensed, semibold, monospaced-digit system font.
    ///
    /// The width matters as much as the size: at SF's standard width a label
    /// sized to `capHeightRatio` runs ~0.86 of the square wide, which is what
    /// squeezed the "%" out entirely. Condensed brings that to ~0.67 — within
    /// a hair of the original badge's proportions — so the percentage fits at
    /// a legible size instead of being dropped.
    private static func font(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold, width: .condensed)
        // `systemFont(ofSize:weight:width:)` has no monospaced-digit variant,
        // so ask for the feature directly. Without it the label reflows as the
        // percentage ticks between values of the same digit count.
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The point size whose cap height hits `capHeightRatio` of the square.
    /// Derived from the font's own metrics rather than a hardcoded 0.72
    /// multiplier, since the system face's cap ratio isn't guaranteed stable.
    private static func fontSize(forCapRatio ratio: CGFloat) -> CGFloat {
        let target = badgeSide * ratio
        let probe = font(ofSize: 100)
        return (target / (probe.capHeight / 100)).rounded(.down)
    }

    /// The point size at which `label` spans exactly `textWidthRatio` of the
    /// square. Glyph advances scale linearly with point size, so this is one
    /// measurement at a reference size rather than a search.
    private static func fontSize(toFitWidthOf label: String) -> CGFloat {
        let target = badgeSide * textWidthRatio
        let probe = (label as NSString).size(withAttributes: [.font: font(ofSize: 100)]).width
        guard probe > 0 else { return minFontSize }
        return target / (probe / 100)
    }

    /// Width-driven, then capped vertically — whichever constraint binds
    /// first. The per-length ceiling is what actually sets the size in
    /// practice; the width clamp stays as the backstop that keeps any label
    /// from running past the square's edges.
    private static func fittedFont(for label: String) -> NSFont {
        let digits = label.filter(\.isNumber).count
        let size = min(fontSize(toFitWidthOf: label),
                       fontSize(forCapRatio: maxCapHeightRatio(forDigits: digits)))
        return font(ofSize: max(size, minFontSize).rounded(.down))
    }

    /// Draws `label` centred in `rect`, using the font's own metrics rather
    /// than the string's bounding box — the latter includes leading, which
    /// pushed the text visibly low in the badge.
    private static func draw(_ label: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let baseline = rect.midY - font.capHeight / 2
        let lineRect = NSRect(
            x: rect.minX,
            y: baseline + font.descender,
            width: rect.width,
            height: font.ascender - font.descender)
        (label as NSString).draw(in: lineRect, withAttributes: attributes)
    }

    private static func square(in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.midX - badgeSide / 2,
            y: rect.midY - badgeSide / 2,
            width: badgeSide,
            height: badgeSide)
    }

    /// A brand-coloured rounded square with the percentage on it, or the
    /// provider's letter when there's no percentage to show yet.
    ///
    /// Deliberately *not* a template image: the whole point is the provider's
    /// brand colour, which template rendering would flatten to monochrome.
    static func badge(pct: Int?, color: NSColor, letter: String) -> NSImage {
        let label = pct.map { "\($0)%" } ?? letter
        let labelFont = fittedFont(for: label)
        let size = NSSize(width: badgeSide, height: slotHeight)
        let radius = badgeSide * cornerRadiusRatio

        let image = NSImage(size: size, flipped: false) { rect in
            let box = square(in: rect)
            color.setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            draw(label, in: box, font: labelFont, color: .white)
            return true
        }

        // The menu bar composites this itself; leaving it non-template keeps
        // the brand colour in both light and dark menu bars.
        image.isTemplate = false
        return image
    }

    /// The "nothing to show yet" badge — the same filled square as the live
    /// one but knocked back, so booting reads differently from a real zero
    /// while staying just as legible, and keeps the same footprint so the bar
    /// doesn't shift once data lands.
    static func placeholder(color: NSColor, letter: String) -> NSImage {
        let size = NSSize(width: badgeSide, height: slotHeight)
        let radius = badgeSide * cornerRadiusRatio
        let glyphFont = font(ofSize: fontSize(forCapRatio: placeholderCapHeightRatio))

        let image = NSImage(size: size, flipped: false) { rect in
            let box = square(in: rect)
            color.withAlphaComponent(placeholderFillAlpha).setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            draw(letter, in: box, font: glyphFont, color: .white)
            return true
        }
        image.isTemplate = false
        return image
    }
}
