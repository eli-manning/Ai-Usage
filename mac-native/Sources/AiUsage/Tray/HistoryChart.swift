import SwiftUI
import UsageCore

/// The usage sparkline — the `drawChart()` canvas from `popup.html`, redrawn
/// with SwiftUI's `Canvas`.
///
/// Points are positioned by their **actual timestamp** within a fixed time
/// window, not by array index. Index-based positions meant every extra refresh
/// (even a manual click seconds after the last) shifted every older point one
/// slot left — spam refresh and the whole visible window collapsed to nearly
/// the same instant, reading as a flat line even when the value hadn't moved.
/// Timestamp positioning means a burst of refreshes piles up at the same x
/// instead of stretching to fill the chart.
struct HistoryChart: View {
    let mode: ChartMode
    let accent: Color
    var height: CGFloat = 52

    private var points: [(t: Date, v: Int)] {
        HistoryStore.shared.points(within: mode.window)
            .compactMap { p in mode.value(p).map { (p.timestamp, $0) } }
    }

    var body: some View {
        let pts = points
        Canvas { context, size in
            guard pts.count >= 2 else { return }

            let padX: CGFloat = 2, padTop: CGFloat = 4, padBottom: CGFloat = 4
            let chartW = size.width - padX * 2
            let chartH = size.height - padTop - padBottom

            // The oldest point in view anchors the left edge (not the window's
            // full theoretical start) so a short history fills the chart as it
            // accumulates instead of being squeezed into a sliver on the right.
            let now = Date()
            let minT = pts[0].t
            let maxT = max(now, pts[pts.count - 1].t)
            // Avoid a divide-by-near-zero when every point shares one instant.
            let span = max(maxT.timeIntervalSince(minT), 60)

            func x(_ t: Date) -> CGFloat { padX + CGFloat(t.timeIntervalSince(minT) / span) * chartW }
            func y(_ v: Int) -> CGFloat { padTop + chartH - CGFloat(v) / 100 * chartH }

            // Reference lines at 50% and 100%.
            for guide in [50, 100] {
                var line = Path()
                line.move(to: CGPoint(x: padX, y: y(guide)))
                line.addLine(to: CGPoint(x: padX + chartW, y: y(guide)))
                context.stroke(line, with: .color(.white.opacity(0.04)), lineWidth: 1)
            }

            let tint = Theme.tier(pts[pts.count - 1].v, accent: accent)

            var line = Path()
            for (i, p) in pts.enumerated() {
                let pt = CGPoint(x: x(p.t), y: y(p.v))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }

            var fill = line
            fill.addLine(to: CGPoint(x: x(pts[pts.count - 1].t), y: padTop + chartH))
            fill.addLine(to: CGPoint(x: x(pts[0].t), y: padTop + chartH))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.25), tint.opacity(0)]),
                startPoint: CGPoint(x: 0, y: padTop),
                endPoint: CGPoint(x: 0, y: padTop + chartH)))

            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            // Emphasise the newest reading — the one the number above refers to.
            let last = pts[pts.count - 1]
            let dot = CGRect(x: x(last.t) - 2.5, y: y(last.v) - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
        }
        .frame(height: height)
        .overlay {
            if pts.count < 2 {
                Text("Not enough data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "383838"))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Week / Session segmented toggle above the chart.
struct ChartModeToggle: View {
    @Binding var mode: ChartMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach([ChartMode.weekly, ChartMode.session], id: \.self) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Text(candidate.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(mode == candidate ? Theme.text : Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(mode == candidate ? Theme.surface : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.dim))
    }
}
