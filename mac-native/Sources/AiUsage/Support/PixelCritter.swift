import AppKit
import SwiftUI

/// A provider's mini standing still, drawn natively from `TraySprites` (the same pixels as the critter on screen),
/// `height` points tall. Used where a page can't go: the notch.
struct PixelCritter: View {
    let provider: String
    var height: CGFloat = 18
    var busy = false

    var body: some View {
        let image = Self.image(provider, mood: busy ? .busy : .fine)
        // One bitmap pixel per critter pixel, scaled up with no smoothing: crisp, and no seams between squares.
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: height * CGFloat(image.width) / CGFloat(image.height), height: height)
    }

    private static var cache: [String: CGImage] = [:]

    /// The sprite as a bitmap, one pixel per critter pixel. Shared with the menu bar icon.
    static func image(_ provider: String, mood: TrayIconRenderer.Mood) -> CGImage {
        let key = "\(provider):\(mood)"
        if let hit = cache[key] { return hit }
        let sprite = TraySprites.all[provider] ?? TraySprites.all["claude"]!
        let rows: [String]
        switch mood {
        case .fine: rows = sprite.fine
        case .busy: rows = sprite.busy
        case .error: rows = sprite.error
        }
        let w = rows.first?.count ?? 1, h = rows.count
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = sprite.palette.map { NSColor(hex: $0).cgColor }
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                guard ch != ".", let a = ch.asciiValue, Int(a) - 97 < colors.count else { continue }
                ctx.setFillColor(colors[Int(a) - 97])
                ctx.fill(CGRect(x: i, y: h - 1 - j, width: 1, height: 1))   // CG's origin is bottom-left
            }
        }
        let image = ctx.makeImage()!
        cache[key] = image
        return image
    }
}
