import SwiftUI

/// The pill style's own visual language — lifted straight from
/// `notch-limits`' `Theme` (dark panel, monospaced "pixel" labels, the same
/// success/warning/danger palette) so this style reads as a faithful port
/// rather than a reinterpretation.
enum PillTheme {
    static let panelBackground = Color.black
    static let rowHover = Color.white.opacity(0.055)
    static let raisedBackground = Color.black
    static let subtleBorder = Color.white.opacity(0.12)
    static let mutedText = Color.white.opacity(0.42)
    static let secondaryText = Color.white.opacity(0.68)
    static let success = Color(red: 0.29, green: 0.85, blue: 0.47)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.36)

    static let cardCornerRadius: CGFloat = 18
    static let pillCornerRadius: CGFloat = 13

    static func pixelFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
