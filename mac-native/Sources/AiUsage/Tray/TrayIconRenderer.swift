import AppKit
import UsageCore

/// Draws the menu bar icon: the selected provider's mini, pixel for pixel the critter on screen
/// (`TraySprites`, made from pet.js), with its usage beside it in Jersey 15.
///
/// Not a template image: the critter's colours are the point. The number takes the bar's own text colour until
/// usage gets high, then turns amber (70%) and red (90%), the same tiers as the dropdown's meters.
enum TrayIconRenderer {

    enum Mood { case fine, busy, error }

    /// The bar's real height. Not `NSStatusBar.system.thickness`, which reports 22 on a notched MacBook whose
    /// bar is really 32pt; `NotchGeometry` resolves the true one.
    private static var slotHeight: CGFloat { NotchGeometry.info().reservedTopHeight }

    /// How tall the critter stands, in points; small critters get chunkier pixels to match the tall ones.
    private static let critterHeight: CGFloat = 18

    static func icon(provider: String, pct: Int?, mood: Mood, darkBar: Bool) -> NSImage {
        let sprite = TraySprites.all[provider] ?? TraySprites.all["claude"]!
        let rows: [String]
        switch mood {
        case .fine: rows = sprite.fine
        case .busy: rows = sprite.busy
        case .error: rows = sprite.error
        }
        let colors = sprite.palette.map { NSColor(hex: $0) }
        // Whole device pixels on a 2x screen: 1, 1.5, 2...
        let px = max(1, ((critterHeight / CGFloat(rows.count)) * 2).rounded(.down) / 2)
        let critter = NSSize(width: CGFloat(rows.first?.count ?? 0) * px, height: CGFloat(rows.count) * px)

        let label = pct.map { "\($0)%" } ?? (mood == .error ? "!" : "")
        let font = PixelFont.ns(21)
        let ink: NSColor
        switch pct ?? 0 {
        case 90...: ink = NSColor(hex: darkBar ? "#FF8A7A" : "#C8382B")
        case 70...: ink = NSColor(hex: darkBar ? "#F2C14E" : "#A86A00")
        default: ink = darkBar ? .white : NSColor(hex: "#1F1A1C")
        }
        let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink])
        let gap: CGFloat = label.isEmpty ? 0 : 4
        let size = NSSize(width: (critter.width + gap + text.size().width).rounded(.up), height: slotHeight)

        let image = NSImage(size: size, flipped: true) { _ in
            let top = ((size.height - critter.height) / 2).rounded()
            for (j, row) in rows.enumerated() {
                for (i, ch) in row.enumerated() {
                    guard let a = ch.asciiValue, ch != ".", Int(a) - 97 < colors.count else { continue }
                    colors[Int(a) - 97].setFill()
                    NSRect(x: CGFloat(i) * px, y: top + CGFloat(j) * px, width: px, height: px).fill()
                }
            }
            // Sit the digits on the critter's feet line, like it's standing next to them.
            let baseline = top + critter.height - 1
            text.draw(at: NSPoint(x: critter.width + gap, y: baseline - font.ascender))
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
