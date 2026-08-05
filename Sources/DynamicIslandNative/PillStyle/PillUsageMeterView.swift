import SwiftUI

/// Ported from `notch-limits`' `UsageMeterView` — a segmented pixel bar
/// instead of a continuous progress ring, matching that app's look exactly.
struct PillUsageMeterView: View {
    let period: PillUsagePeriod
    let accentColor: Color

    private let segmentCount = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(period.label.uppercased())
                    .foregroundStyle(PillTheme.secondaryText)

                Text(percentText)
                    .foregroundStyle(meterColor)

                Spacer(minLength: 2)

                if let resetText = period.resetText, !resetText.isEmpty {
                    Text(resetText.uppercased())
                        .foregroundStyle(PillTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .font(PillTheme.pixelFont(size: 9, weight: .semibold))

            PillMeter(fraction: period.fractionUsed ?? 0, segmentCount: segmentCount, color: meterColor)
                .frame(height: 5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(PillTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(PillTheme.subtleBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var percentText: String {
        guard let fraction = period.fractionUsed else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private var meterColor: Color {
        guard let fraction = period.fractionUsed else { return PillTheme.mutedText }
        if fraction >= 0.9 { return PillTheme.danger }
        if fraction >= 0.7 { return PillTheme.warning }
        return accentColor
    }
}

private struct PillMeter: View {
    let fraction: Double
    let segmentCount: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let width = max(1, (proxy.size.width - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount))
            let filled = Int(ceil(max(0, min(1, fraction)) * Double(segmentCount)))

            HStack(spacing: gap) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? color : Color.white.opacity(0.1))
                        .frame(width: width)
                }
            }
        }
    }
}
