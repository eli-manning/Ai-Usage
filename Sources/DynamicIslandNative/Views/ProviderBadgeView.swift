import SwiftUI

/// The minimal "logo + percentage" chip from the fan style's rest-state bar
/// (`MenuBarChromeView`'s `badge`/`percentageLabel`), pulled out so the pill
/// style's collapsed indicator can reuse the exact same look instead of
/// reimplementing it.
struct ProviderBadgeView: View {
    let provider: Provider
    var size: CGFloat = 19
    var iconSize: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().fill(provider.color)
            BrandIconView(d: provider.icon, size: iconSize, color: .white)
        }
        .frame(width: size, height: size)
    }
}

struct ProviderPercentageLabel: View {
    let pct: Int?
    let fallbackText: String

    var body: some View {
        if let pct {
            Text("\(pct)%")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Format.statusColor(pct))
                .fixedSize()
        } else {
            Text(fallbackText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize()
        }
    }
}
