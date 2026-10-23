import AppKit
import SwiftUI

/// Jersey 15, the pixel font every page speaks in (Resources/web/fonts), for the native bits: the menu bar icon
/// and the notch. Loaded straight from the file, so nothing gets installed system-wide.
enum PixelFont {
    private static let descriptor: CTFontDescriptor? = {
        guard let url = Web.dir?.appendingPathComponent("fonts/Jersey15.ttf"),
              let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        return all.first
    }()

    static func ns(_ size: CGFloat) -> NSFont {
        guard let descriptor else { return .monospacedDigitSystemFont(ofSize: size * 0.8, weight: .semibold) }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    static func font(_ size: CGFloat) -> Font { Font(ns(size) as CTFont) }
}
