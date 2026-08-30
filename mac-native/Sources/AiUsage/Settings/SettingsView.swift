import AppKit
import SwiftUI
import UsageCore

/// The Settings window — the native replacement for `settings.html`, plus the
/// display-mode switch that the Electron build had no way to offer.
struct SettingsView: View {
    @ObservedObject var usage: UsageService

    @State private var displayMode = Settings.shared.displayMode
    @State private var launchAtLogin = Settings.shared.launchAtLogin
    /// Mirrors the persisted map so toggles re-render immediately rather than
    /// waiting for the (possibly slow) refresh that follows.
    @State private var enabled = Settings.shared.providerEnabled

    var onDisplayModeChange: (DisplayMode) -> Void
    var onRunWizard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                appearanceSection
                providersSection
                generalSection
            }
            .padding(22)
        }
        .frame(width: 460, height: 620)
        .background(Theme.bg)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection(
            title: "Appearance",
            caption: "Where usage lives while the app is running."
        ) {
            VStack(spacing: 10) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    DisplayModeRow(
                        mode: mode,
                        isSelected: displayMode == mode,
                        isAvailable: available(mode),
                        unavailableReason: unavailableReason(mode)
                    ) {
                        guard available(mode) else { return }
                        displayMode = mode
                        Settings.shared.displayMode = mode
                        onDisplayModeChange(mode)
                    }
                }
            }
        }
    }

    /// The notch shell has nowhere to live on a display without a notch — it
    /// fuses to the hardware cutout rather than floating near it, so offering
    /// it on a Mac mini or an external monitor would just produce a pill
    /// hanging in dead space.
    private func available(_ mode: DisplayMode) -> Bool {
        mode == .tray || NotchGeometry.hasHardwareNotch
    }

    private func unavailableReason(_ mode: DisplayMode) -> String? {
        guard !available(mode) else { return nil }
        return "This display has no notch."
    }

    // MARK: - Providers

    private var providersSection: some View {
        SettingsSection(
            title: "Providers",
            caption: "Switching one off stops this app from launching its CLI at all."
        ) {
            VStack(spacing: 0) {
                ForEach(Array(Provider.all.enumerated()), id: \.element.id) { index, provider in
                    ProviderRow(
                        provider: provider,
                        status: usage.status(provider.id),
                        isEnabled: enabled[provider.id] ?? true,
                        onToggle: { on in
                            enabled[provider.id] = on
                            Task { await usage.setProviderEnabled(provider.id, on) }
                        })
                    if index < Provider.all.count - 1 {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, lineWidth: 1)))
        }
    }

    // MARK: - General

    private var generalSection: some View {
        SettingsSection(title: "General", caption: nil) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at login")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Open AI Usage automatically when you log in.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            Settings.shared.launchAtLogin = newValue
                            LoginItem.setEnabled(newValue)
                        }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.green)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup wizard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Walk through detection and sign-in again.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Run", action: onRunWizard)
                        .buttonStyle(PillButtonStyle())
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stored data")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Settings and usage history live in Application Support.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(
                            nil, inFileViewerRootedAtPath: Settings.supportDirectory.path)
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        }
    }
}

// MARK: - Pieces

struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Theme.muted)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
    }
}

struct DisplayModeRow: View {
    let mode: DisplayMode
    let isSelected: Bool
    let isAvailable: Bool
    let unavailableReason: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                DisplayModePreview(mode: mode, tint: isSelected ? Theme.text : Theme.muted)
                    .frame(width: 62, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isAvailable ? Theme.text : Theme.muted)
                    Text(unavailableReason ?? mode.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.green : Theme.dim)
                    .padding(.top, 2)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Theme.green.opacity(0.5) : Theme.border,
                                lineWidth: 1)))
            .contentShape(Rectangle())
            .opacity(isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}

/// A tiny diagram of where each shell puts itself, so the choice reads without
/// having to try both.
struct DisplayModePreview: View {
    let mode: DisplayMode
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.dim, lineWidth: 1))

                // The menu bar itself.
                Rectangle()
                    .fill(Theme.dim)
                    .frame(height: 6)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))

                switch mode {
                case .tray:
                    // A badge sitting at the right end of the menu bar.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tint)
                        .frame(width: 11, height: 4)
                        .offset(x: w / 2 - 10, y: 1)
                case .notch:
                    // A pill fused to the centre cutout, hanging below it.
                    UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                        .fill(tint)
                        .frame(width: 22, height: 9)
                }
            }
            .frame(width: w, height: h)
        }
    }
}

struct ProviderRow: View {
    let provider: Provider
    let status: ProviderStatus
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 11) {
            BrandIconView(d: provider.iconPath, size: 17, color: provider.color)
                .opacity(isEnabled ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isEnabled ? Theme.text : Theme.muted)
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isEnabled, let action = primaryAction {
                Button(action.title, action: action.run)
                    .buttonStyle(PillButtonStyle())
            }

            Toggle("", isOn: Binding(get: { isEnabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.green)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var statusText: String {
        guard isEnabled else { return "Turned off." }
        switch status.state {
        case .checking: return "Checking…"
        case .notInstalled: return "Not installed."
        case .installed: return "Installed — not signed in."
        case .loggedIn: return status.message.map { "Signed in (\($0))" } ?? "Signed in."
        case .error(let message): return message
        case .disabled: return "Turned off."
        }
    }

    private var statusColor: Color {
        guard isEnabled else { return Theme.muted }
        switch status.state {
        case .loggedIn: return status.message == nil ? Theme.green : Theme.yellow
        case .error: return Theme.red
        default: return Theme.muted
        }
    }

    /// Install beats log-in beats nothing: whichever one actually unblocks the
    /// user from here.
    private var primaryAction: (title: String, run: () -> Void)? {
        switch status.state {
        case .notInstalled:
            if let command = provider.installCommand {
                return ("Install", { TerminalLauncher.run(command) })
            }
            if let urlString = provider.installURL, let url = URL(string: urlString) {
                return ("Docs", { NSWorkspace.shared.open(url) })
            }
            return nil
        case .installed, .error:
            return provider.loginCommand.map { cmd in ("Log in", { TerminalLauncher.run(cmd) }) }
        default:
            return nil
        }
    }
}
