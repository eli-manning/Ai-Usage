#!/usr/bin/env swift
//
// Renders the app icon master PNG.
//
// Run through `scripts/make-icons.sh`, which turns the output into the macOS
// `.icns` and the PNG that electron-builder derives the Windows `.ico` from.
// Kept as a script rather than a package target: it runs when the artwork
// changes, not on every build, and its output is committed.
//
// The mark is the notch panel's radial ring of provider wedges — four arcs in
// the four provider brand colours on the app's own near-black — so the icon in
// Applications reads as the same app as the thing in the menu bar.
import AppKit

let size: CGFloat = 1024
// macOS icons are inset inside their 1024 canvas rather than bleeding to the
// edge; 824pt of art with a 185.4pt corner radius is the standard grid.
let inset: CGFloat = 100
let artSize = size - inset * 2
let cornerRadius: CGFloat = 185.4

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1)
}

// Theme.bg / Theme.surface, and the four Provider.colorHex values in tab order.
let backgroundTop = color("1C1C1C")
let backgroundBottom = color("0B0B0B")
let wedgeColors = [color("CC785C"), color("4E8CFF"), color("3ECF8E"), color("8B7CF6")]

// An explicit 1024x1024 bitmap rep, not `NSImage.lockFocus()` — the latter
// picks up the current display's backing scale and quietly emits a 2048px
// image on a Retina Mac, which `iconutil` then rejects as the wrong size.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext

ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

// Rounded-square plate.
let art = CGRect(x: inset, y: inset, width: artSize, height: artSize)
let plate = CGPath(roundedRect: art, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                   transform: nil)
ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
if let gradient = CGGradient(colorsSpace: space,
                             colors: [backgroundTop.cgColor, backgroundBottom.cgColor] as CFArray,
                             locations: [0, 1]) {
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: art.minX, y: art.maxY),
                           end: CGPoint(x: art.maxX, y: art.minY),
                           options: [])
}
ctx.restoreGState()

// A hairline rim, the same trick Theme.border plays in the popover — it keeps
// the plate from dissolving into a dark wallpaper behind it.
ctx.saveGState()
ctx.addPath(plate)
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.06).cgColor)
ctx.setLineWidth(5)
ctx.strokePath()
ctx.restoreGState()

// The ring of provider wedges. Drawn as four stroked arcs with a gap between
// them, starting at 12 o'clock and running clockwise the way the notch ring does.
let center = CGPoint(x: size / 2, y: size / 2)
let ringRadius: CGFloat = 268
let ringWidth: CGFloat = 92
let gapDegrees: CGFloat = 6
let sweep = (360.0 / CGFloat(wedgeColors.count)) - gapDegrees

// Faint full-circle track behind the wedges, so a provider that's switched off
// still reads as a slot rather than a hole.
ctx.saveGState()
ctx.setLineWidth(ringWidth)
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.06).cgColor)
ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2,
           clockwise: false)
ctx.strokePath()
ctx.restoreGState()

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

for (index, wedgeColor) in wedgeColors.enumerated() {
    // CoreGraphics angles run counter-clockwise from 3 o'clock; 90° is the top.
    let start = 90 - CGFloat(index) * (sweep + gapDegrees) - gapDegrees / 2
    let end = start - sweep
    ctx.saveGState()
    ctx.setLineWidth(ringWidth)
    // Butt caps, not round: round ones bulge past the arc's own endpoints and
    // swallow the gaps that separate one provider's wedge from the next.
    ctx.setLineCap(.butt)
    ctx.setStrokeColor(wedgeColor.cgColor)
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: radians(start), endAngle: radians(end), clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()
}

// The percent sign at the hub — what the badge actually shows all day.
let hub = "%" as NSString
let font = NSFont.systemFont(ofSize: 300, weight: .semibold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color("E6E6E6"),  // Theme.text
]
let textSize = hub.size(withAttributes: attributes)
hub.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
         withAttributes: attributes)

NSGraphicsContext.restoreGraphicsState()

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
