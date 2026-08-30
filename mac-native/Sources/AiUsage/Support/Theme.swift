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

    /// Spelled `icon` as well as `iconPath` because the notch views were
    /// written against the standalone app's own Provider, which used the
    /// shorter name; keeping both avoids touching 41KB of working view code.
    var icon: String { iconPath }

    /// The Simple Icons brand mark for this provider. Path data lives in
    /// `BrandIcon` rather than alongside the rest of the provider row because
    /// it's several KB of geometry per mark, and it changes far less often.
    var iconPath: String {
        switch id {
        case "claude": return BrandIcon.claude
        case "antigravity": return BrandIcon.gemini
        case "codex": return BrandIcon.codex
        case "cursor": return BrandIcon.cursor
        default: return BrandIcon.claude
        }
    }
}

/// The palette, carried over from `popup.html`'s CSS custom properties so the
/// native popover reads as the same app rather than a redesign.
enum Theme {
    static let bg = Color(hex: "0F0F0F")
    static let surface = Color(hex: "181818")
    static let border = Color(hex: "242424")
    static let dim = Color(hex: "2A2A2A")
    static let text = Color(hex: "E6E6E6")
    static let muted = Color(hex: "505050")
    static let green = Color(hex: "4DB876")
    static let yellow = Color(hex: "D4A843")
    static let red = Color(hex: "C95C5C")

    static let cornerRadius: CGFloat = 12

    /// Usage-tier colour. `accent` is the selected provider's own brand colour,
    /// used for the healthy band so the whole panel re-themes per provider —
    /// but the warning and danger bands stay fixed, because "you are nearly out
    /// of quota" must not read differently depending on which tab you're on.
    static func tier(_ pct: Int?, accent: Color) -> Color {
        guard let pct else { return muted }
        if pct >= 90 { return red }
        if pct >= 70 { return yellow }
        return accent
    }
}

enum Format {

    /// The notch's own palette for a usage figure — brighter than the
    /// popover's, because it renders as text directly on the black bump
    /// rather than as a bar on a panel.
    static func statusColor(_ pct: Int?) -> Color {
        guard let pct else { return .white.opacity(0.5) }
        if pct >= 90 { return Color(hex: "E0857C") }
        if pct >= 70 { return Color(hex: "E6BD6B") }
        return .white
    }

    /// The same tiers as `statusColor`, but saturated for fills and arcs
    /// rather than text.
    static func statusHex(_ pct: Int?) -> Color {
        guard let pct else { return .white.opacity(0.3) }
        if pct >= 90 { return Color(hex: "D1685F") }
        if pct >= 70 { return Color(hex: "D4A843") }
        return Color(hex: "CC785C")
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
