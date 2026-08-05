import SwiftUI

/// Ported from `notch-limits`' `NotchExpandedContent` — the overview strip,
/// one row per provider, and a footer with pin/refresh/settings controls.
struct PillExpandedContent: View {
    @ObservedObject var usage: UsageService
    let onOpenSettings: () -> Void

    private var snapshots: [PillProviderSnapshot] { PillUsageAdapter.snapshots(from: usage) }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(snapshots) { snapshot in
                PillProviderRow(
                    snapshot: snapshot,
                    status: usage.providers[snapshot.provider.id] ?? ProviderStatus(state: .checking),
                    onOpenSettings: onOpenSettings
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 7)
    }
}

private struct PillProviderRow: View {
    let snapshot: PillProviderSnapshot
    let status: ProviderStatus
    let onOpenSettings: () -> Void

    @State private var isHovering = false


    var body: some View {
        HStack(spacing: 10) {
            BrandIconView(d: snapshot.provider.icon, size: 24, color: snapshot.provider.color)

            identity
                .frame(width: 106, alignment: .leading)

            statusContent
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(isHovering ? PillTheme.rowHover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.name)
                .font(PillTheme.pixelFont(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(snapshot.accountEmail ?? "")
                .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                .foregroundStyle(PillTheme.mutedText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch snapshot.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(snapshot.provider.color)
                Text("CHECKING \(snapshot.provider.name.uppercased())\u{2026}")
                    .font(PillTheme.pixelFont(size: 9, weight: .medium))
                    .foregroundStyle(PillTheme.secondaryText)
                Spacer()
            }
        case .notConnected, .installed:
            HStack {
                Text("CONNECT THIS ACCOUNT IN SETTINGS")
                    .font(PillTheme.pixelFont(size: 8.5, weight: .medium))
                    .foregroundStyle(PillTheme.mutedText)
                Spacer()
                Button("SETTINGS", action: onOpenSettings)
                    .buttonStyle(PillAccentButtonStyle(color: snapshot.provider.color))
            }
        case .failed(let message):
            HStack(spacing: 7) {
                Circle().fill(PillTheme.danger).frame(width: 6, height: 6)
                Text(message.uppercased())
                    .font(PillTheme.pixelFont(size: 8.5, weight: .medium))
                    .foregroundStyle(PillTheme.danger.opacity(0.9))
                    .lineLimit(2)
                Spacer()
            }
        case .loaded:
            HStack(spacing: 7) {
                ForEach(Array(snapshot.periods.prefix(2))) { period in
                    PillUsageMeterView(period: period, accentColor: snapshot.provider.color)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}


private struct PillAccentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PillTheme.pixelFont(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(color.opacity(configuration.isPressed ? 0.22 : 0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
