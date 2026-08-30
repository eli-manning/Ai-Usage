import SwiftUI
import UsageCore

/// One labelled percentage with its bar and reset line — the `statHTML()`
/// helper from `popup.html`, as a view.
struct StatGauge: View {
    let label: String
    let pct: Int?
    var reset: String? = nil
    var sub: String? = nil
    let accent: Color

    private var tier: Color { Theme.tier(pct, accent: accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Format.pct(pct))
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.55)
                }
                .foregroundStyle(tier)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.dim)
                    Capsule()
                        .fill(tier)
                        .frame(width: geo.size.width * CGFloat(min(max(pct ?? 0, 0), 100)) / 100)
                }
            }
            .frame(height: 3)
            // The bar is decorative; the number above it is the accessible value.
            .accessibilityHidden(true)

            if let reset = Format.reset(reset) {
                Text(reset)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(pct.map { "\($0) percent used" } ?? "not available")
    }
}

/// The banner shown over otherwise-valid cached data when the latest refresh
/// failed — the point being that stale real numbers beat an error screen.
struct StaleBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(message)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.yellow)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Theme.yellow.opacity(0.25), lineWidth: 1)))
        .padding(.horizontal, 13)
        .padding(.top, 10)
    }
}

/// The centred message used for every "nothing to show" state — not installed,
/// not signed in, still checking, or switched off.
struct EmptyStateView: View {
    let title: String
    var hint: String? = nil
    var isError = false
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isError ? Theme.red : Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(configuration.isPressed ? Theme.dim : Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1)))
            .contentShape(Capsule())
    }
}
