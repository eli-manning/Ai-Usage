import SwiftUI
import UsageCore

extension Color {
    init(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }
}

extension Provider {
    var color: Color { Color(hex: colorHex) }
}

/// Mochi's palette (pet.css, ui.css), for the native bits that sit beside the pages: the notch's fan is the same
/// paper and ink as every panel.
enum Theme {
    static let paper = Color(hex: "FFFAF3")
    static let soft = Color(hex: "F3E9DD")
    static let ink = Color(hex: "2A1D1A")
    static let muted = Color(hex: "8D7A6E")

    /// A usage figure printed on paper: ink, then amber past 70%, red past 90%. Same tiers as the dropdown.
    static func inkTier(_ pct: Int?) -> Color {
        guard let pct else { return muted }
        if pct >= 90 { return Color(hex: "C8382B") }
        if pct >= 70 { return Color(hex: "A86A00") }
        return ink
    }

    /// The same tiers as a fill: the provider's own colour while it's fine.
    static func fillTier(_ pct: Int, accent: Color) -> Color {
        if pct >= 90 { return Color(hex: "D9483B") }
        if pct >= 70 { return Color(hex: "E0A43B") }
        return accent
    }
}

enum Format {

    /// A usage figure printed on the black bar beside the notch: white, then
    /// a light amber and red, bright enough to read on black.
    static func statusColor(_ pct: Int?) -> Color {
        guard let pct else { return .white.opacity(0.5) }
        if pct >= 90 { return Color(hex: "E0857C") }
        if pct >= 70 { return Color(hex: "E6BD6B") }
        return .white
    }

    /// "just now" / "5m ago" / "3h ago" — the freshness label.
    static func ago(_ date: Date?) -> String {
        guard let date else { return "never" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    /// Tidies a CLI's own reset string for display.
    ///
    /// Drops the parenthesised timezone (nobody needs "(America/Los_Angeles)"
    /// in a 300px panel) and repairs the two spacing artefacts the TUI's
    /// column packing introduces.
    static func reset(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        var out = Pattern(#"\s*\([^)]*\)"#).replacingAll(in: s, with: "")
        out = Pattern(#"([A-Za-z])(\d)"#).replacingAll(in: out, with: "$1 $2")   // "Mar5" → "Mar 5"
        out = Pattern(#",(\S)"#).replacingAll(in: out, with: ", $1")             // "Mar 5,8pm" → "Mar 5, 8pm"
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func pct(_ value: Int?) -> String {
        value.map { "\($0)" } ?? "—"
    }
}
