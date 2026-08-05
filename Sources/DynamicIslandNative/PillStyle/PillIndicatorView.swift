import SwiftUI

/// Ported from `notch-limits`' `NotchPillView` — the collapsed row of tiny
/// per-provider dots, and the expanded header with a pin toggle. Reads
/// snapshots derived from this app's own `UsageService` rather than a
/// separate usage store.
struct PillIndicatorView: View {
    @ObservedObject var viewModel: PillViewModel
    let snapshots: [PillProviderSnapshot]
    let layout: PillNotchLayout
    let onOpenSettings: () -> Void


    /// Room reserved either side of the real notch for the badge/percentage
    /// — same idea as the fan style's own `NotchGeometry.Layout.flankWidth`,
    /// just derived from this style's own widened collapsed width instead
    /// of duplicating that constant.
    private var flankWidth: CGFloat { (layout.collapsedSize.width - layout.notchFrame.width) / 2 }

    var body: some View {
        Group {
            if viewModel.isExpanded {
                expandedHeader
            } else {
                collapsedIndicator
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.isExpanded)
    }

    /// Collapsed state reuses the fan style's own minimal "logo +
    /// percentage" chip (`ProviderBadgeView`/`ProviderPercentageLabel`)
    /// rather than notch-limits' row of tiny dashes — showing whichever
    /// provider is currently "hottest" (same provider the expanded header's
    /// overview strip already highlights), since the pill style has no
    /// hover-to-switch provider picker of its own.
    /// Badge on one side of the real notch, percentage on the other — the
    /// gap between them (`layout.notchFrame.width` wide) is exactly the
    /// notch's own footprint, so neither ever sits behind the physical
    /// camera housing itself. Mirrors the fan style's own
    /// `MenuBarChromeView`, which keeps the same gap for the same reason.
    private var collapsedIndicator: some View {
        HStack(spacing: 0) {
            ProviderBadgeView(provider: hottest?.provider ?? Provider.all[0])
                .frame(width: flankWidth)
            Spacer(minLength: layout.notchFrame.width)
            collapsedPercentageText
                .frame(width: flankWidth)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .accessibilityLabel("Ai Usage")
    }

    /// Uses the pill style's own threshold colors (`PillTheme.danger`/
    /// `.warning`, same bright red/amber `PillUsageMeterView` already uses)
    /// rather than the fan's own `Format.statusColor`, so a percentage read
    /// here matches what the expanded card would show for the same number.
    private var collapsedPercentageText: some View {
        Group {
            if let pct = hottest?.pct {
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .bold))
            } else {
                Text(fallbackText)
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
        .foregroundColor(collapsedPercentageColor)
        .fixedSize()
    }

    private var collapsedPercentageColor: Color {
        guard let hottest else { return PillTheme.mutedText }
        let fraction = Double(hottest.pct) / 100
        if fraction >= 0.9 { return PillTheme.danger }
        if fraction >= 0.7 { return PillTheme.warning }
        return hottest.provider.color
    }

    private var hottest: (provider: Provider, pct: Int)? {
        snapshots
            .compactMap { snapshot in snapshot.worstFraction.map { (snapshot.provider, Int(($0 * 100).rounded())) } }
            .max { $0.pct < $1.pct }
    }

    private var fallbackText: String {
        guard let snapshot = snapshots.first(where: { $0.provider.id == (hottest?.provider.id ?? Provider.all[0].id) }) else {
            return "…"
        }
        switch snapshot.state {
        case .checking: return "…"
        case .notConnected: return "n/a"
        case .installed: return "sign in"
        case .failed: return "error"
        case .loaded: return "…"
        }
    }

    private var expandedHeader: some View {
        HStack {
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PillTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
        }
        .padding(.horizontal, 14)
    }

}
